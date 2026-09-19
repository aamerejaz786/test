function [T, ByCombo, Overall] = a02(rootDir, outDir)
% A02
% Merge distributed DV-Hop shard MAT files into the same final outputs as
% the original 9000-trial experiment.
%
% Usage:
%   [T, ByCombo, Overall] = a02('shard_results','final_results');
%
% The function:
%   1) finds every DVHOP_FAST_9000_RESULTS.mat recursively under rootDir,
%   2) concatenates the per-trial T tables,
%   3) verifies exactly 9000 unique (ComboID,Trial) rows,
%   4) verifies 90 combos and exactly 100 trials per combo,
%   5) recomputes ByCombo and Overall from the merged 9000 rows,
%   6) writes the final CSV and MAT files.

if nargin < 1 || strlength(string(rootDir)) == 0
    rootDir = 'shard_results';
end
if nargin < 2 || strlength(string(outDir)) == 0
    outDir = 'final_results';
end
rootDir = char(rootDir);
outDir = char(outDir);

files = dir(fullfile(rootDir, '**', 'DVHOP_FAST_9000_RESULTS.mat'));
assert(~isempty(files), 'No shard MAT files found under: %s', rootDir);

Tall = cell(numel(files),1);
shardCompute_s = nan(numel(files),1);
shardIDs = nan(numel(files),1);
numShardsSeen = nan(numel(files),1);

fprintf('Found %d shard MAT files.\n', numel(files));
for i = 1:numel(files)
    f = fullfile(files(i).folder, files(i).name);
    S = load(f, 'T', 'Overall');
    assert(isfield(S,'T') && istable(S.T), 'Missing table T in %s', f);
    Tall{i} = S.T;

    if isfield(S,'Overall') && istable(S.Overall) && height(S.Overall) >= 1
        if ismember('ComputeTime_s', S.Overall.Properties.VariableNames)
            shardCompute_s(i) = S.Overall.ComputeTime_s(1);
        end
        if ismember('ShardID', S.Overall.Properties.VariableNames)
            shardIDs(i) = S.Overall.ShardID(1);
        end
        if ismember('NumShards', S.Overall.Properties.VariableNames)
            numShardsSeen(i) = S.Overall.NumShards(1);
        end
    end
    fprintf('  loaded %d/%d: %s (%d rows)\n', i, numel(files), f, height(S.T));
end

T = vertcat(Tall{:});
T = sortrows(T, {'ComboID','Trial'});

% ---------------- integrity checks ----------------
assert(height(T) == 9000, ...
    'Expected 9000 merged rows, but found %d.', height(T));

keys = [double(T.ComboID), double(T.Trial)];
[~, ia] = unique(keys, 'rows', 'stable');
assert(numel(ia) == height(T), ...
    'Duplicate (ComboID,Trial) rows detected: %d duplicates.', height(T)-numel(ia));

assert(numel(unique(T.ComboID)) == 90, ...
    'Expected 90 unique ComboID values, found %d.', numel(unique(T.ComboID)));

[Gcombo, comboKey] = findgroups(T.ComboID);
comboCounts = splitapply(@numel, T.Trial, Gcombo);
assert(all(comboCounts == 100), ...
    'Every combo must contain exactly 100 trials after merge.');
assert(numel(comboKey) == 90, 'Expected 90 combo groups after merge.');

expectedTrials = (1:100).';
for c = 1:90
    got = sort(T.Trial(T.ComboID == c));
    assert(isequal(double(got(:)), double(expectedTrials)), ...
        'ComboID %d does not contain exactly Trial 1..100.', c);
end

fprintf('Integrity check PASSED: 9000 unique rows, 90 combos, 100 trials/combo.\n');

% ---------------- final summaries ----------------
[ByCombo, Overall] = summarizeFastResultsMerged(T);

finiteCompute = shardCompute_s(isfinite(shardCompute_s));
if isempty(finiteCompute)
    Overall.ComputeTime_s = NaN;
    Overall.ComputeTime_min = NaN;
    Overall.SumShardComputeTime_s = NaN;
    Overall.SumShardComputeTime_min = NaN;
else
    % For distributed execution, the maximum shard compute time is the best
    % approximation of parallel experiment compute wall time. Sum is also
    % retained as aggregate compute consumed across all shard jobs.
    Overall.ComputeTime_s = max(finiteCompute);
    Overall.ComputeTime_min = Overall.ComputeTime_s/60;
    Overall.SumShardComputeTime_s = sum(finiteCompute);
    Overall.SumShardComputeTime_min = Overall.SumShardComputeTime_s/60;
end
Overall.ShardsMerged = numel(files);
if any(isfinite(numShardsSeen))
    Overall.ConfiguredNumShards = max(numShardsSeen(isfinite(numShardsSeen)));
else
    Overall.ConfiguredNumShards = numel(files);
end

if ~exist(outDir,'dir'), mkdir(outDir); end
rawCsv = fullfile(outDir,'DVHOP_FAST_9000_PER_TRIAL.csv');
byCsv  = fullfile(outDir,'DVHOP_FAST_9000_BY_COMBO.csv');
ovCsv  = fullfile(outDir,'DVHOP_FAST_9000_OVERALL.csv');
matFile= fullfile(outDir,'DVHOP_FAST_9000_RESULTS.mat');

writetable(T, rawCsv);
writetable(ByCombo, byCsv);
writetable(Overall, ovCsv);
save(matFile,'T','ByCombo','Overall','shardCompute_s','shardIDs','numShardsSeen');

fprintf('\nFINAL MERGE COMPLETE.\n');
fprintf('  Per-trial rows : %d\n', height(T));
fprintf('  Combo rows     : %d\n', height(ByCombo));
fprintf('  Output folder  : %s\n', outDir);
fprintf('  Per-trial CSV  : %s\n', rawCsv);
fprintf('  By-combo CSV   : %s\n', byCsv);
fprintf('  Overall CSV    : %s\n', ovCsv);
fprintf('  MAT file       : %s\n', matFile);
end

function [B, O] = summarizeFastResultsMerged(T)
% Same scientific aggregation as dvhop_fast_final_9000_v2/v3.
Gvars = {'ComboID','AreaSize','CommRange','TotalNodes','AnchorPct','NumAnchors','NumUnknowns'};
[G,Key] = findgroups(T(:,Gvars));
meanNaN = @(x) mean(x,'omitnan');
stdNaN  = @(x) std(x,'omitnan');
medNaN  = @(x) median(x,'omitnan');

B = Key;
B.TrialsRequested = splitapply(@numel,T.Trial,G);
B.TrialsOK        = splitapply(@(x)sum(x=="OK"),T.Status,G);
B.SuccessfulTrialPct = 100 * B.TrialsOK ./ max(B.TrialsRequested,1);

% ---------------- Errors ----------------
B.MeanErr_T = splitapply(meanNaN,T.Error_T,G);
B.StdErr_T  = splitapply(stdNaN,T.Error_T,G);
B.MeanErr_M = splitapply(meanNaN,T.Error_M,G);
B.StdErr_M  = splitapply(stdNaN,T.Error_M,G);
B.MeanErr_P_Selected = splitapply(meanNaN,T.Error_P_Selected,G);
B.StdErr_P_Selected  = splitapply(stdNaN,T.Error_P_Selected,G);
B.MedianErr_P_Selected = splitapply(medNaN,T.Error_P_Selected,G);
B.MeanErr_P_AllAnchors = splitapply(meanNaN,T.Error_P_AllAnchors,G);
B.MeanErr_PreCollinear = splitapply(meanNaN,T.Error_PreCollinear,G);
B.MeanErr_PostCollinear = splitapply(meanNaN,T.Error_PostCollinear,G);
B.StdErr_PostCollinear  = splitapply(stdNaN,T.Error_PostCollinear,G);

% ---------------- Coverage / robustness ----------------
B.MeanCoverage_T_pct = splitapply(meanNaN,T.Coverage_T_pct,G);
B.MeanCoverage_M_pct = splitapply(meanNaN,T.Coverage_M_pct,G);
B.MeanCoverage_P_Selected_pct = splitapply(meanNaN,T.Coverage_P_Selected_pct,G);
B.MeanCoverage_P_AllAnchors_pct = splitapply(meanNaN,T.Coverage_P_AllAnchors_pct,G);
B.MeanCoverage_PreCollinear_pct = splitapply(meanNaN,T.Coverage_PreCollinear_pct,G);
B.MeanCoverage_PostCollinear_pct= splitapply(meanNaN,T.Coverage_PostCollinear_pct,G);
B.Robust_T_pct = 100*splitapply(@(x)mean(isfinite(x)),T.Error_T,G);
B.Robust_M_pct = 100*splitapply(@(x)mean(isfinite(x)),T.Error_M,G);
B.Robust_P_Selected_pct = 100*splitapply(@(x)mean(isfinite(x)),T.Error_P_Selected,G);

% ---------------- Anchors / collinearity ----------------
B.MeanAnchors_MOANS = splitapply(meanNaN,T.AnchorsUsed_MOANS,G);
B.MeanAnchors_P_Selected = splitapply(meanNaN,T.AnchorsUsed_P_Selected,G);
B.MeanAnchors_BeforeCollinear = splitapply(meanNaN,T.Anchors_BeforeCollinear,G);
B.MeanAnchors_AfterCollinear = splitapply(meanNaN,T.Anchors_AfterCollinear,G);
B.MeanCollinearRemoved = splitapply(meanNaN,T.CollinearRemovedCount,G);
B.MeanCollinearRemovedPct = splitapply(meanNaN,T.CollinearRemovedPct,G);
B.ProposedAllAnchorUsage_pct = 100*splitapply(meanNaN,T.ProposedUsedAllAnchors,G);
B.ProposedFewerAnchorsThanMOANS_pct = 100*splitapply(meanNaN,T.ProposedUsesFewerAnchorsThanMOANS,G);

% ---------------- GDOP ----------------
B.MeanGDOP_P_Selected = splitapply(meanNaN,T.MeanGDOP_P_Selected,G);
B.MedianGDOP_P_Selected = splitapply(medNaN,T.MedianGDOP_P_Selected,G);
B.MeanGDOP_AllAnchors = splitapply(meanNaN,T.MeanGDOP_AllAnchors,G);
B.MeanGDOP_PreCollinear = splitapply(meanNaN,T.MeanGDOP_PreCollinear,G);
B.MeanGDOP_PostCollinear= splitapply(meanNaN,T.MeanGDOP_PostCollinear,G);
B.MeanGDOP_MOANS = splitapply(meanNaN,T.MeanGDOP_MOANS,G);

% ---------------- Connectivity ----------------
B.AvgPhysicalEdges = splitapply(meanNaN,T.PhysicalEdges,G);
B.AvgGraphDensity_pct = splitapply(meanNaN,T.GraphDensity_pct,G);
B.AvgMeanNodeDegree = splitapply(meanNaN,T.MeanNodeDegree,G);
B.AvgStdNodeDegree = splitapply(meanNaN,T.StdNodeDegree,G);
B.AvgMinNodeDegree = splitapply(meanNaN,T.MinNodeDegree,G);
B.AvgMaxNodeDegree = splitapply(meanNaN,T.MaxNodeDegree,G);
B.AvgIsolatedNodes = splitapply(meanNaN,T.IsolatedNodes,G);
B.AvgConnectedComponents = splitapply(meanNaN,T.ConnectedComponents,G);
B.AvgLargestComponentNodes = splitapply(meanNaN,T.LargestComponentNodes,G);
B.AvgLargestComponent_pct = splitapply(meanNaN,T.LargestComponent_pct,G);
B.FullyConnectedTrials_pct = 100*splitapply(meanNaN,T.FullyConnected,G);
B.AvgMeanAnchorDegree = splitapply(meanNaN,T.MeanAnchorDegree,G);
B.AvgMeanUnknownDegree = splitapply(meanNaN,T.MeanUnknownDegree,G);
B.AvgReachableAnchorUnknownPairs_pct = splitapply(meanNaN,T.ReachableAnchorUnknownPairs_pct,G);
B.AvgUnknownsReachableFrom3PlusAnchors_pct = splitapply(meanNaN,T.UnknownsReachableFrom3PlusAnchors_pct,G);
B.AvgReachableAnchorsPerUnknown = splitapply(meanNaN,T.MeanReachableAnchorsPerUnknown,G);
B.AvgMinReachableAnchorsPerUnknown = splitapply(meanNaN,T.MinReachableAnchorsPerUnknown,G);
B.AvgMaxReachableAnchorsPerUnknown = splitapply(meanNaN,T.MaxReachableAnchorsPerUnknown,G);
B.AvgMeanAnchorUnknownHop = splitapply(meanNaN,T.MeanAnchorUnknownHop,G);
B.AvgMedianAnchorUnknownHop = splitapply(meanNaN,T.MedianAnchorUnknownHop,G);
B.AvgAnchorPairReachability_pct = splitapply(meanNaN,T.AnchorPairReachability_pct,G);
B.AvgMeanAnchorAnchorHop = splitapply(meanNaN,T.MeanAnchorAnchorHop,G);
B.AvgMedianAnchorAnchorHop = splitapply(meanNaN,T.MedianAnchorAnchorHop,G);

% ---------------- Wins / comparisons ----------------
B.MeanGain_TminusP_m = splitapply(meanNaN,T.Gain_TminusP_m,G);
B.MeanGain_MminusP_m = splitapply(meanNaN,T.Gain_MminusP_m,G);
B.MeanGain_AllminusP_m = splitapply(meanNaN,T.Gain_AllminusP_m,G);
B.WinRate_P_vs_T_pct = 100*splitapply(meanNaN,T.ProposedBeatsTraditional,G);
B.WinRate_P_vs_M_pct = 100*splitapply(meanNaN,T.ProposedBeatsMOANS,G);
B.WinRate_P_vsBoth_pct = 100*splitapply(meanNaN,T.ProposedBeatsBoth,G);
B.MeanErrorChange_PreMinusPostCollinear_m = splitapply(meanNaN,T.ErrorChange_PreMinusPostCollinear_m,G);
B.MeanGDOPChange_PreMinusPostCollinear = splitapply(meanNaN,T.GDOPChange_PreMinusPostCollinear,G);
B.PostCollinearBetterError_pct = 100*splitapply(meanNaN,T.PostCollinearBetterError,G);

% ---------------- Time ----------------
B.MeanTime_T_s = splitapply(meanNaN,T.Time_T_s,G);
B.MeanTime_M_s = splitapply(meanNaN,T.Time_M_s,G);
B.MeanTime_P_Selected_Total_s = splitapply(meanNaN,T.Time_P_Selected_Total_s,G);
B.MeanTime_P_AllAnchors_s = splitapply(meanNaN,T.Time_P_AllAnchors_s,G);
B.MeanTime_PostCollinear_s = splitapply(meanNaN,T.Time_PostCollinear_s,G);
B.MeanTrialWallTime_s = splitapply(meanNaN,T.TrialWallTime_s,G);

% ---------------- Paired tests ----------------
B.P_T_vs_P_Selected = splitapply(@pairedPFastMerged,T.Error_T,T.Error_P_Selected,G);
B.P_M_vs_P_Selected = splitapply(@pairedPFastMerged,T.Error_M,T.Error_P_Selected,G);
B.P_Pre_vs_PostCollinear = splitapply(@pairedPFastMerged,T.Error_PreCollinear,T.Error_PostCollinear,G);

% ---------------- Whole experiment ----------------
O = table();
O.TotalTrials = height(T);
O.TrialsOK = sum(T.Status=="OK");
O.UniqueCombos = height(B);
O.MeanErr_T = mean(T.Error_T,'omitnan');
O.MeanErr_M = mean(T.Error_M,'omitnan');
O.MeanErr_P_Selected = mean(T.Error_P_Selected,'omitnan');
O.MeanErr_P_AllAnchors = mean(T.Error_P_AllAnchors,'omitnan');
O.MeanErr_PreCollinear = mean(T.Error_PreCollinear,'omitnan');
O.MeanErr_PostCollinear = mean(T.Error_PostCollinear,'omitnan');
O.MeanCoverage_T_pct = mean(T.Coverage_T_pct,'omitnan');
O.MeanCoverage_M_pct = mean(T.Coverage_M_pct,'omitnan');
O.MeanCoverage_P_Selected_pct = mean(T.Coverage_P_Selected_pct,'omitnan');
O.MeanAnchors_P_Selected = mean(T.AnchorsUsed_P_Selected,'omitnan');
O.ProposedAllAnchorUsage_pct = 100*mean(T.ProposedUsedAllAnchors,'omitnan');
O.ProposedFewerAnchorsThanMOANS_pct = 100*mean(T.ProposedUsesFewerAnchorsThanMOANS,'omitnan');
O.MeanCollinearRemovedPct = mean(T.CollinearRemovedPct,'omitnan');
O.MeanGDOP_P_Selected = mean(T.MeanGDOP_P_Selected,'omitnan');
O.MeanGDOP_PreCollinear = mean(T.MeanGDOP_PreCollinear,'omitnan');
O.MeanGDOP_PostCollinear = mean(T.MeanGDOP_PostCollinear,'omitnan');
O.WinRate_P_vsBoth_pct = 100*mean(T.ProposedBeatsBoth,'omitnan');
O.PostCollinearBetterError_pct = 100*mean(T.PostCollinearBetterError,'omitnan');
O.AvgGraphDensity_pct = mean(T.GraphDensity_pct,'omitnan');
O.AvgMeanNodeDegree = mean(T.MeanNodeDegree,'omitnan');
O.AvgConnectedComponents = mean(T.ConnectedComponents,'omitnan');
O.FullyConnectedTrials_pct = 100*mean(T.FullyConnected,'omitnan');
O.AvgLargestComponent_pct = mean(T.LargestComponent_pct,'omitnan');
O.AvgReachableAnchorUnknownPairs_pct = mean(T.ReachableAnchorUnknownPairs_pct,'omitnan');
O.AvgUnknownsReachableFrom3PlusAnchors_pct = mean(T.UnknownsReachableFrom3PlusAnchors_pct,'omitnan');
O.AvgReachableAnchorsPerUnknown = mean(T.MeanReachableAnchorsPerUnknown,'omitnan');
O.AvgAnchorPairReachability_pct = mean(T.AnchorPairReachability_pct,'omitnan');
O.MeanTrialWallTime_s = mean(T.TrialWallTime_s,'omitnan');
end

function p = pairedPFastMerged(a,b)
good = isfinite(a) & isfinite(b);
a = a(good); b = b(good);
if numel(a) < 2
    p = NaN; return;
end
if exist('ttest','file')==2
    try
        [~,p] = ttest(a,b);
    catch
        p = NaN;
    end
else
    p = NaN;
end
end
