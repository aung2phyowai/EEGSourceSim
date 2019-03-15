% This Script generates simulation for a network of three interconnected nodes
% including three ROIs: V1d, V3d and TO1
% Author: Elham Barzegaran, 1/2019

clear; clc;
SimFolder = fileparts(pwd);
addpath(genpath(SimFolder));
addpath(genpath(fullfile('..','BrainNetSimulation')));% add BrainNet Toolbox
% requires fieldtrip for WPLI calculation

%% Prepare the results folders
FigPath = 'Figures';
ResultPath = 'ResultData';
if ~exist(fullfile(pwd,FigPath),'dir'),mkdir(FigPath);end
if ~exist(fullfile(pwd,ResultPath),'dir'),mkdir(ResultPath);end

%% Redo Simulation?
simulateEEG = 0; % if simulateEEG = 0, then it loads in the data otherwise do the simulation using Simulate functions

%% Prepare Project path and ROIs
DestPath = fullfile(SimFolder,'Examples','ExampleData_Inverse');
AnatomyPath = fullfile(DestPath,'anatomy');
ProjectPath = fullfile(DestPath,'FwdProject');

[RoiList,subIDs] = mrC.Simulate.GetRoiClass(ProjectPath,AnatomyPath);% 13 subjects with Wang atlab 
V1_RoiList = cellfun(@(x) {x.searchROIs('V1d','wang','L')},RoiList);
V3_RoiList = cellfun(@(x) {x.searchROIs('V3d','wang','L')},RoiList);
TO1_RoiList = cellfun(@(x) {x.searchROIs('TO1','wang','L')},RoiList);
Net_RoiList = cellfun(@(x,y,z) {mergROIs(mergROIs(x,y),z)},V1_RoiList,V3_RoiList,TO1_RoiList);

All_RoiList = Net_RoiList;

%% Load in wang ROIs and inverses
% load(fullfile(ResultPath,'ROI_colors_Paper.mat'));

Wang_RoiList = cellfun(@(x) {x.getAtlasROIs('wang')},RoiList);
Wang_Chunks = cellfun(@(x) x.ROI2mat(20484),Wang_RoiList,'uni',false);

Inverse = mrC.Simulate.ReadInverses(ProjectPath,'mneInv_bem_gcv_regu_TWindow_0_1334_wangROIsCorr.inv');

%% Prepare background activity

% load simulation signal
% NOTE: this signal is generated by running ARSIgnalGenerate.m and BrainNetSimulation Toolbox
load(fullfile('private','NetTimeSeries_3Nodes'));
SF = Net_connect.SF;
eplength = 2*SF; % two seconds
epNum = 15;
TS_all = TS_connect(1:3,1:epNum*eplength);
TS_all_UC = TS_unconnect(1:3,1:epNum*eplength);

%% Simulating network

ModeNames= {'connect','unconnect'};
Noise.lambda = 0;
if ~exist(fullfile(ResultPath,'ConnectitvityExampleData.mat'),'file') || simulateEEG
        SignalArray = reshape(TS_all(:,1:epNum*eplength)',eplength,15,size(TS_all,1));
        
        [EEGData_noise,~,EEGData_signal_connect,~,~,masterList,subIDs] = mrC.Simulate.SimulateProject(ProjectPath,'anatomyPath',AnatomyPath,...
            'signalArray',SignalArray,'signalsf',SF,'NoiseParams',Noise,'rois',All_RoiList,...
            'Save',false,'cndNum',1,'doSource' ,true,'signalSNRFreqBand',[5 15],...
            'doFwdProjectNoise',true,'RedoMixingMatrices',false,'nTrials',epNum);

        SignalArray = reshape(TS_all_UC(:,1:15*eplength)',eplength,15,size(TS_all_UC,1));
        [~,~,EEGData_signal_unconnect] = mrC.Simulate.SimulateProject(ProjectPath,'anatomyPath',AnatomyPath,...
            'signalArray',SignalArray,'signalsf',SF,'NoiseParams',Noise,'rois',All_RoiList,...
            'Save',false,'cndNum',1,'doSource' ,true,'signalSNRFreqBand',[5 15],...
            'doFwdProjectNoise',true,'RedoMixingMatrices',false,'nTrials',epNum);
        
    save(fullfile(ResultPath,'ConnectitvityExampleData.mat'),'EEGData_noise','EEGData_signal_connect','EEGData_signal_unconnect','subIDs','masterList');
else
    load(fullfile(ResultPath,'ConnectitvityExampleData.mat'));
end
%% prepare the EEGs based on different SNR levels
dB_list = [-25:5:10] ; 
Lambda_list = 10.^(dB_list/10) ;

f = [0:eplength-1] *SF/eplength ;
SNR_freq_idxs = (f>=5)&(f<=25);
if true
    for subj_idx = 1:length(subIDs)
        %
        spec_noise = fft(EEGData_noise{subj_idx},[],1);
        spec_signalC = fft(EEGData_signal_connect{subj_idx},[],1);
        spec_signalNC = fft(EEGData_signal_unconnect{subj_idx},[],1);
        power_noise = mean(mean(abs(spec_noise(SNR_freq_idxs,:,:)).^2)) ; % mean noise power per trial
        power_signalC= mean(mean(abs(spec_signalC(SNR_freq_idxs,:,:)).^2)) ;
        power_signalNC= mean(mean(abs(spec_signalNC(SNR_freq_idxs,:,:)).^2)) ; 
        EEGData_noise{subj_idx} = EEGData_noise{subj_idx}./sqrt(power_noise);
        EEGData_signal_connect{subj_idx} = EEGData_signal_connect{subj_idx}./sqrt(power_signalC);
        EEGData_signal_unconnect{subj_idx} = EEGData_signal_unconnect{subj_idx}./sqrt(power_signalNC);
    end

    % Generate EEG, calculate sources and then power spectra
    for nLambda_idx = 1:numel(Lambda_list)
        lambda = Lambda_list(nLambda_idx);
        disp(['Generating EEG by adding signal and noise: SNR = ' num2str(lambda)]);
        for subj_idx = 1:length(subIDs)
            EEGData_C{subj_idx} = sqrt(lambda/(1+lambda))*EEGData_signal_connect{subj_idx} + sqrt(1/(1+lambda)) * EEGData_noise{subj_idx} ;
            for tr = 1:epNum
                ROIData{subj_idx}(:,:,tr) = EEGData_C{subj_idx}(:,:,tr)*Inverse{subj_idx}*Wang_Chunks{subj_idx}./repmat(sum(Wang_Chunks{subj_idx}), [eplength 1]);
            end
            [CSD_C{subj_idx,nLambda_idx},COH_C{subj_idx,nLambda_idx}] = mrC.Connectivity.EEGcpsd(ROIData{subj_idx} ,'SF',SF,'Type','fft','winLen',300,'Nov',150);
            %EEGData_NC{subj_idx} = sqrt(lambda/(1+lambda))*EEGData_signal_unconnect{subj_idx} + sqrt(1/(1+lambda)) * EEGData_noise{subj_idx} ;
        end
    end

    save(fullfile(ResultPath,'ConnectivityExampleResults.mat'),'CSD_C','COH_C','subIDs','masterList');
else
    load(fullfile(ResultPath,'ConnectivityExampleResults.mat'));
end
%%
%load(fullfile(ResultPath,'ConnectivityExampleResults.mat'));

ModeNames= {'connect','unconnect'};
ConMeasures = {'RCOH','RWPLI'};

% Frequencies
LF = 9;HF = 22;
Freqs = [LF HF];
ref = zeros(50,50,2); ref(25,41,1)=1;ref(29,41,1)=1;ref(25,29,1)=1;%real connection
ref(25,29,2)=1;%real connection
% ROIS
Labels = [Wang_RoiList{1}.getFullNames('noatlashemi')];
Labels{25} = '\color[rgb]{0,1,0}\rightarrow TO1';
Labels{29} = '\color[rgb]{0,0,1}\rightarrow V1d';
Labels{41} = '\color[rgb]{1,0,0}\rightarrow V3d';
INDs = [1:2:25 29:2:50];

 
for L = 1:numel(Lambda_list)

    % subsampling
    R_coh = COH_C(:,L);
    NTS = numel(R_coh);% number of total samples
    BS = nchoosek(1:NTS,5);
    Nboots = 80;%size(BS,1)/2;
    BS = BS(randperm(size(BS,1),Nboots),:);
    
    % Prepare ICOH and WPLI for plotting
    for boots = 1:Nboots
        display(['Bootstrapping #' num2str(boots)]);
        R_coh = COH_C(:,L);
        R_coh = R_coh(BS(boots,:));
        R_coh = cat(4,R_coh{:}); % Recons
        RCOH(:,:,:,L) = squeeze(mean(imag(R_coh),4));

        % wPLI
        % Prepare spectrum inputs
        RCSD = CSD_C(:,L);
        RCSD = RCSD(BS(boots,:));
        RCSD = cat(4,RCSD{:}); %  Recons
        RCSD = permute(RCSD,[4 2 3 1]);


        % fieldtrip is needed
        R_wpli = ft_connectivity_wpli(RCSD,'dojack',true);
        RWPLI(:,:,:,L) = permute(R_wpli,[3 1 2]);
        % calculate TP and FPs
        th = 0:.0001:1; % Thresholds for PR and ROC curves
        %th = 1-th.^3;

        for t = 1:numel(th)
            for conM = 1:numel(ConMeasures)
                for F = 1:numel(Freqs)
                    eval(['D = squeeze(abs(' ConMeasures{conM} '(Freqs(F),:,:,L)));']);
                    %D = (D-min(D(:)))/(max(D(:))-min(D(:)));
                    D(1:length(D)+1:end)=0;
                    Dif = triu((D>th(t)).*(ref(:,:,F)==0));
                    tp = triu((D>th(t)).*ref(:,:,F));
                    TP(t,boots,conM,F,L) = sum(tp(:));
                    FP(t,boots,conM,F,L) = sum(Dif(:));
                end
            end
        end
    end
end

save(fullfile(ResultPath,'Connectivity_Bootstrap_TPFP2.mat'),'TP','FP','RCOH','RWPLI');

%%
%load(fullfile(ResultPath,'Connectivity_Bootstrap_TPFP2.mat'));
FontS = 12;
TPM = squeeze(mean(TP,2));
FPM = squeeze(mean(FP,2));

FIG = figure;
Cs = colormap(cool(10));%[ones(10,1)*.3 ones(10,1)*.3 (0.1:0.1:1)'];
N = 2:2:10;
%CondNames = {'Original','Reconstructed','Original','Reconstructed'};
S1 = subplot(3,2,3);
FOI = 1;
%
% for l =1:numel(dB_list)
%     for cond = 1:2
%         perc = squeeze(TPM(:,cond,FOI,l))./(squeeze(TPM(:,cond,FOI,l))+squeeze(FPM(:,cond,FOI,l)));
%         perc(isnan(perc))=0;
%         rec = squeeze(TPM(:,cond,FOI,l))/3;
%         AUC(cond,l) = trapz(rec,perc);
% 
%     end
% end
% S = subplot(2,1,2);
% B = bar(abs(AUC)','grouped');
%%%%%%
for l =1:numel(dB_list)
    for cond = 1:2
        for b = 1:Nboots
            perc = squeeze(TP(:,b,cond,FOI,l))./(squeeze(TP(:,b,cond,FOI,l))+squeeze(FP(:,b,cond,FOI,l)));
            perc(isnan(perc))=0;
            rec = squeeze(TP(:,b,cond,FOI,l))/3;
            AUC(cond,l,b) = trapz(rec,perc);
        end
    end
    [~,p_AUC(l)]= ttest(AUC(1,l,:),AUC(2,l,:));
end

AUCM = mean(AUC,3);AUCM = abs(AUCM([1 2],:))';
AUCS = std(AUC,[],3)./sqrt(Nboots);AUCS = abs(AUCS([1 2],:))';
XT = [(1:size(AUC,2))-.15;(1:size(AUC,2))+.15];
S = subplot(2,1,2);
B = bar(AUCM,'grouped');hold on; 
errorbar(reshape(XT,1,numel(XT)),reshape(AUCM',1,numel(AUCM)),reshape(AUCS',1,numel(AUCS)),'.k')

for r = 1:size(XT,2)
    if p_AUC(r)<0.05
        line(XT(:,r),[max(AUCM(r,:)+AUCS(r,:)) max(AUCM(r,:)+AUCS(r,:))]+0.02,'color','k','linewidth',2)
        text(r-.05,max(AUCM(r,:)+AUCS(r,:))+.03,'*','fontsize',FontS)
    end
end

set(B(1),'FaceColor',[0.3,.3,.3])
set(B(2),'FaceColor',[.7,.7,.7])
xlim([0 numel(dB_list)+1])
ylim([0 .52])
legend('ICoh','WPLI')
set(gca,'xticklabel',arrayfun(@(x) [num2str(dB_list(x))],1:numel(dB_list),'uni',false))
ylabel('AUCPR','fontsize',FontS)
xlabel('SNR [dB]','fontsize',FontS);
set(gca,'fontsize',FontS)
set(S,'position',get(S,'position')+[-.0 -.02 .0 -.045]);




% Plotting connectivity matrices
CondNames = {'ICoh','WPLI'};
ConMeasures = {'RCOH','RWPLI'};

SNRs = [3];
for i = 1:numel(SNRs)
    for j = 1:numel(ConMeasures)
        eval(['P =  abs(squeeze(' ConMeasures{j} '(Freqs(FOI),INDs,INDs,SNRs(i))));']);
        S(i,j) = subplot(2,2,j);
        imagesc(P.^2)
        if j==1
            set(gca,'xtick',1:numel(INDs),'xticklabels',Labels(INDs),'ytick',1:numel(INDs),'yticklabels',Labels(INDs));
            ylabel('SNR = -15 dB','fontsize',FontS);
        else
            set(gca,'xtick',1:numel(INDs),'xticklabels',Labels(INDs),'ytick',1:numel(INDs),'yticklabels',Labels(INDs));
        end
        xtickangle(90)
        set(gca,'fontsize',12)
        caxis([0 max(P(:).^2)]);
        colormap(jmaColors('hotcortex'));
%         if (i == numel(SNRs)) && (j==1)
%             ylabel('ROIs','fontsize',FontS-8);
%             xlabel('ROIs','fontsize',FontS-8);
%         end
        title(CondNames{j},'fontsize',FontS);
        switch j
            case 2
                colorbar;
                set(S(i,j),'position',get(S(i,j),'position')+[ -.025 -.1 .02 .12]);
            case 1
                set(S(i,j),'position',get(S(i,j),'position')+[ 0 -.1 .02 .12])
        end
    end
end


set(FIG,'paperposition',[1 1 9 7.2]);
set(FIG,'Unit','Inch','position',[1 1 9 7.2],'color','w');

 print(fullfile('Figures','ConnectivityExample_AUCPR2_high.tif'),'-r300','-dtiff');
 export_fig(FIG,fullfile('Figures','ConnectivityExample_AUCPR2_high'),'-pdf');

