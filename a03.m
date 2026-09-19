function [T, ByCombo, Overall] = a03()
% DVHOP_FAST_FINAL_9000_V2
% Fast final DV-Hop experiment runner with full per-trial, per-combo,
% collinearity, selected-anchor, GDOP, all-anchor and connectivity results.
%
% EXACT experimental grid (paired area/node scenarios):
%   Area 100 x 100 -> 100 total nodes
%   Area 200 x 200 -> 200 total nodes
%   Area 500 x 500 -> 300 total nodes
%   Communication range = [15 20 25 30 35 40]
%   Anchor percent       = [10 15 20 25 30]
%   Trials per combo     = 100
%   Total combos         = 3 * 6 * 5 = 90
%   Total trials         = 90 * 100 = 9000
%
% OUTPUT LEVELS:
%   1) PER TRIAL: one row for every run (9000 rows)
%   2) BY COMBO : one aggregate row for every 100-run combo (90 rows)
%   3) OVERALL  : one aggregate row for the complete experiment
%
% PER-TRIAL RESULT GROUPS:
%   - Traditional DV-Hop
%   - MOANS
%   - Proposed final selected-anchor result
%   - Proposed using ALL anchors
%   - Before collinearity removal (= all available anchors)
%   - After collinearity removal
%   - Selected anchor IDs
%   - 2-D GDOP for MOANS / Proposed / all / pre / post collinearity
%   - Connectivity metrics for the physical graph and effective DV-Hop reachability
%   - Runtime and direct method comparisons
%
% CONNECTIVITY METRICS:
%   PhysicalEdges, GraphDensity_pct, Mean/Std/Min/MaxNodeDegree,
%   IsolatedNodes, ConnectedComponents, LargestComponentNodes,
%   LargestComponent_pct, FullyConnected, MeanAnchorDegree,
%   MeanUnknownDegree, ReachableAnchorUnknownPairs_pct,
%   UnknownsReachableFrom3PlusAnchors_pct,
%   Mean/Min/MaxReachableAnchorsPerUnknown,
%   Mean/MedianAnchorUnknownHop,
%   AnchorPairReachability_pct, Mean/MedianAnchorAnchorHop.
%
% SPEED DESIGN:
%   - No tuning scan; only final 90 combos.
%   - parfor across trials when available.
%   - Anchor-source shortest paths only (A x N, not N x N all-pairs hops).
%   - No per-trial file writes, figures, or verbose candidate printing.
%   - Result files are written once, after all simulations finish.
%
% Save as:
%   dvhop_fast_final_9000_v2.m
% Run:
%   [T, ByCombo, Overall] = dvhop_fast_final_9000_v2;

close all; clc;
set(0,'DefaultFigureVisible','off');

global DVHOP_VERBOSE;
DVHOP_VERBOSE = false;

%% ========================= FINAL EXPERIMENT CONFIG ========================
TopologyTag       = "C-Shape";
ScenarioAreas     = [100 200 500];
ScenarioNodes     = [100 200 300];   % PAIRED with ScenarioAreas
CommRangeList     = [15 20 25 30 35 40];
AnchorPctList     = [10 15 20 25 30];
TrialsPerCombo    = 100;

NoiseStd          = 0.01;
MaxHopCap         = 12;
UseIntegerHops    = true;
DropRate          = 0;

% Final Proposed settings. Change only if these are not your selected values.
AA = struct('filteringMode','moderate', ...
            'minAnchorsFrac',0.70, ...
            'rescueAcceptFactor',1.30);

MOANS_MODE = 'safe';

%% ============================== SPEED ====================================
USE_PARALLEL = true;
NUM_WORKERS  = 4;     % Safe starting point for a 12-GB laptop.
WRITE_XLSX   = false; % Keep false for fastest run; CSV + MAT are always written.

runStamp = datestr(now,'yyyymmdd_HHMMSS');
outDir = fullfile(pwd, ['dvhop_fast_9000_v2_' runStamp]);
if ~exist(outDir,'dir'), mkdir(outDir); end

%% ========================= BUILD 90 COMBOS ================================
comboArea = zeros(90,1);
comboN    = zeros(90,1);
comboR    = zeros(90,1);
comboPct  = zeros(90,1);
c = 0;
for s = 1:numel(ScenarioAreas)
    for r = 1:numel(CommRangeList)
        for p = 1:numel(AnchorPctList)
            c = c + 1;
            comboArea(c) = ScenarioAreas(s);
            comboN(c)    = ScenarioNodes(s);
            comboR(c)    = CommRangeList(r);
            comboPct(c)  = AnchorPctList(p);
        end
    end
end
nCombos = c;
assert(nCombos == 90, 'Expected exactly 90 combinations.');

TotalRuns = nCombos * TrialsPerCombo;
fprintf('DV-Hop FINAL FAST RUN V2\n');
fprintf('  Combos           : %d\n', nCombos);
fprintf('  Trials per combo : %d\n', TrialsPerCombo);
fprintf('  Total trials     : %d\n', TotalRuns);
fprintf('  Proposed AA      : filter=%s, minFrac=%.2f, rescue=%.2f\n', ...
    AA.filteringMode, AA.minAnchorsFrac, AA.rescueAcceptFactor);

runCombo = repelem((1:nCombos).', TrialsPerCombo);
runTrial = repmat((1:TrialsPerCombo).', nCombos, 1);

%% ========================= START PARALLEL POOL ============================
useParallelNow = false;
if USE_PARALLEL
    try
        if license('test','Distrib_Computing_Toolbox')
            pool = gcp('nocreate');
            if isempty(pool)
                pool = parpool('local', NUM_WORKERS);
            end
            fprintf('  Parallel workers : %d\n', pool.NumWorkers);
            useParallelNow = true;
        else
            fprintf('  Parallel toolbox : unavailable -> serial fallback\n');
        end
    catch ME
        fprintf('  Parallel startup failed (%s) -> serial fallback\n', ME.message);
        useParallelNow = false;
    end
end

%% ============================= 9000 RUNS =================================
blank = makeEmptyFastRecord();
records = repmat(blank, TotalRuns, 1);

tCompute = tic;
if useParallelNow
    parfor k = 1:TotalRuns
        cid = runCombo(k);
        records(k) = runSingleFastTrial( ...
            cid, runTrial(k), ...
            comboArea(cid), comboN(cid), comboR(cid), comboPct(cid), ...
            TopologyTag, NoiseStd, MaxHopCap, UseIntegerHops, DropRate, ...
            AA, MOANS_MODE);
    end
else
    for k = 1:TotalRuns
        cid = runCombo(k);
        records(k) = runSingleFastTrial( ...
            cid, runTrial(k), ...
            comboArea(cid), comboN(cid), comboR(cid), comboPct(cid), ...
            TopologyTag, NoiseStd, MaxHopCap, UseIntegerHops, DropRate, ...
            AA, MOANS_MODE);
        if mod(k,100)==0
            fprintf('  Completed %d/%d trials (%.1f%%)\n', k, TotalRuns, 100*k/TotalRuns);
        end
    end
end
computeSeconds = toc(tCompute);

%% ============================ BUILD TABLES ================================
T = struct2table(records);

firstCols = {'ComboID','AreaSize','CommRange','TotalNodes','AnchorPct', ...
             'NumAnchors','NumUnknowns','Trial','Seed','Status', ...
             'NoiseStd','MaxHopCap','DropRate','UseIntegerHops'};
otherCols = setdiff(T.Properties.VariableNames, firstCols, 'stable');
T = T(:, [firstCols otherCols]);

[ByCombo, Overall] = summarizeFastResults(T);
Overall.ComputeTime_s = computeSeconds;
Overall.ComputeTime_min = computeSeconds/60;

%% ============================= WRITE ONCE ================================
tWrite = tic;
rawCsv = fullfile(outDir,'DVHOP_FAST_9000_PER_TRIAL.csv');
byCsv  = fullfile(outDir,'DVHOP_FAST_9000_BY_COMBO.csv');
ovCsv  = fullfile(outDir,'DVHOP_FAST_9000_OVERALL.csv');
matFile= fullfile(outDir,'DVHOP_FAST_9000_RESULTS.mat');

writetable(T, rawCsv);
writetable(ByCombo, byCsv);
writetable(Overall, ovCsv);
save(matFile,'T','ByCombo','Overall');

if WRITE_XLSX
    xlsxFile = fullfile(outDir,'DVHOP_FAST_9000_RESULTS.xlsx');
    writetable(T,       xlsxFile, 'Sheet','per_trial');
    writetable(ByCombo, xlsxFile, 'Sheet','by_combo');
    writetable(Overall, xlsxFile, 'Sheet','overall');
end
writeSeconds = toc(tWrite);

fprintf('\nDONE.\n');
fprintf('  Compute time : %.2f min\n', computeSeconds/60);
fprintf('  Write time   : %.2f min\n', writeSeconds/60);
fprintf('  Output folder: %s\n', outDir);
fprintf('  Per-trial CSV: %s\n', rawCsv);
fprintf('  By-combo CSV : %s\n', byCsv);
fprintf('  Overall CSV  : %s\n', ovCsv);
fprintf('  MAT file     : %s\n', matFile);

end

%% ========================================================================
function rec = runSingleFastTrial(comboID, trialNo, areaSize, N, commRange, pct, ...
    topologyTag, noiseStd, maxHopCap, useIntegerHops, dropRate, AA, moansMode)

rec = makeEmptyFastRecord();
trialWall = tic;

rec.ComboID       = comboID;
rec.AreaSize      = areaSize;
rec.CommRange     = commRange;
rec.TotalNodes    = N;
rec.AnchorPct     = pct;
rec.Trial         = trialNo;
rec.Topology      = string(topologyTag);
rec.NoiseStd      = noiseStd;
rec.MaxHopCap     = maxHopCap;
rec.DropRate      = dropRate;
rec.UseIntegerHops= double(logical(useIntegerHops));

seed = uint32(100000 + comboID*1000 + trialNo);
rec.Seed = double(seed);

try
    rng(seed,'twister');

    numAnchors = max(3, round(N*pct/100));
    numAnchors = min(numAnchors, N-3);
    numUnknowns = N - numAnchors;

    rec.NumAnchors  = numAnchors;
    rec.NumUnknowns = numUnknowns;

    innerRadius = 0.20 * areaSize; %#ok<NASGU>
    anchorPos   = generateOShapePositions(numAnchors,  areaSize, areaSize, innerRadius);
    unknownPos  = generateOShapePositions(numUnknowns, areaSize, areaSize, innerRadius);
    allPos      = [anchorPos; unknownPos];

    simParams = struct();
    simParams.dropRate       = dropRate;
    simParams.noiseStdRange  = [noiseStd noiseStd];
    simParams.maxHopCap      = maxHopCap;
    simParams.useIntegerHops = logical(useIntegerHops);
    simParams.seed           = double(seed);
    simParams.moansMode      = moansMode;

    % FAST hop graph + connectivity diagnostics from the same physical graph.
    [hopCount, conn] = buildAnchorHopGraphFast(allPos, numAnchors, commRange, simParams);
    adjMatrix = [];

    % Store connectivity metrics in this trial row.
    rec.PhysicalEdges = conn.PhysicalEdges;
    rec.GraphDensity_pct = conn.GraphDensity_pct;
    rec.MeanNodeDegree = conn.MeanNodeDegree;
    rec.StdNodeDegree = conn.StdNodeDegree;
    rec.MinNodeDegree = conn.MinNodeDegree;
    rec.MaxNodeDegree = conn.MaxNodeDegree;
    rec.IsolatedNodes = conn.IsolatedNodes;
    rec.ConnectedComponents = conn.ConnectedComponents;
    rec.LargestComponentNodes = conn.LargestComponentNodes;
    rec.LargestComponent_pct = conn.LargestComponent_pct;
    rec.FullyConnected = conn.FullyConnected;
    rec.MeanAnchorDegree = conn.MeanAnchorDegree;
    rec.MeanUnknownDegree = conn.MeanUnknownDegree;
    rec.ReachableAnchorUnknownPairs_pct = conn.ReachableAnchorUnknownPairs_pct;
    rec.UnknownsReachableFrom3PlusAnchors_pct = conn.UnknownsReachableFrom3PlusAnchors_pct;
    rec.MeanReachableAnchorsPerUnknown = conn.MeanReachableAnchorsPerUnknown;
    rec.MinReachableAnchorsPerUnknown = conn.MinReachableAnchorsPerUnknown;
    rec.MaxReachableAnchorsPerUnknown = conn.MaxReachableAnchorsPerUnknown;
    rec.MeanAnchorUnknownHop = conn.MeanAnchorUnknownHop;
    rec.MedianAnchorUnknownHop = conn.MedianAnchorUnknownHop;
    rec.AnchorPairReachability_pct = conn.AnchorPairReachability_pct;
    rec.MeanAnchorAnchorHop = conn.MeanAnchorAnchorHop;
    rec.MedianAnchorAnchorHop = conn.MedianAnchorAnchorHop;

    % ---------------- Traditional ----------------
    tt = tic;
    [eT, estT] = runTraditionalDVHop(anchorPos, unknownPos, allPos, ...
        hopCount, adjMatrix, commRange, areaSize, simParams);
    rec.Time_T_s = toc(tt);
    rec.Error_T = eT;
    rec.Coverage_T_pct = coverageFast(estT);

    % ---------------- MOANS ----------------
    tm = tic;
    [eM, estM, selM] = runMOANSDVHop(anchorPos, unknownPos, allPos, ...
        hopCount, adjMatrix, commRange, areaSize, simParams);
    rec.Time_M_s = toc(tm);
    rec.Error_M = eM;
    rec.Coverage_M_pct = coverageFast(estM);
    rec.AnchorsUsed_MOANS = numel(selM);
    rec.SelectedAnchorIDs_MOANS = idxToStringFast(selM);

    % ---------------- Proposed selected + all-anchor diagnostic ----------------
    tp = tic;
    [eP, estP, nUsedP, finalIdxP, eAll, estAll, covAll, timeAll] = ...
        runProposed_Enriched(anchorPos, unknownPos, allPos, ...
            hopCount, adjMatrix, commRange, areaSize, simParams, AA, eT, eM);
    rec.Time_P_Selected_Total_s = toc(tp);

    rec.Error_P_Selected         = eP;
    rec.Coverage_P_Selected_pct  = coverageFast(estP);
    rec.AnchorsUsed_P_Selected   = nUsedP;
    rec.SelectedAnchorIDs_P      = idxToStringFast(finalIdxP);

    rec.Error_P_AllAnchors        = eAll;
    rec.Coverage_P_AllAnchors_pct = covAll;
    rec.AnchorsUsed_P_AllAnchors  = numAnchors;
    rec.Time_P_AllAnchors_s       = timeAll;
    rec.ProposedUsedAllAnchors    = double(numel(finalIdxP)==numAnchors && ...
                                            isequal(sort(finalIdxP(:)), (1:numAnchors).'));

    % ---------------- BEFORE / AFTER collinearity removal ----------------
    beforeIdx = (1:numAnchors).';
    rec.Anchors_BeforeCollinear = numAnchors;
    rec.AnchorIDs_BeforeCollinear = idxToStringFast(beforeIdx);
    rec.Error_PreCollinear = eAll;
    rec.Coverage_PreCollinear_pct = covAll;

    paramsCol = local_adaptThresholdsLite(anchorPos, hopCount, ...
        commRange, numAnchors, AA.filteringMode);
    afterIdx = removeCollinearBasic(anchorPos, paramsCol.minAreaTri);
    if numel(afterIdx) < 3
        afterIdx = beforeIdx;
    end
    rec.Anchors_AfterCollinear = numel(afterIdx);
    rec.AnchorIDs_AfterCollinear = idxToStringFast(afterIdx);
    rec.CollinearRemovedCount = numAnchors - numel(afterIdx);
    rec.CollinearRemovedPct = 100 * rec.CollinearRemovedCount / max(numAnchors,1);

    tc = tic;
    estAfter = estimateUnknownsWithAnchorsProposed( ...
        hopCount, anchorPos(afterIdx,:), afterIdx, unknownPos, ...
        numAnchors, areaSize, commRange, allPos, simParams, 0);
    rec.Time_PostCollinear_s = toc(tc);
    rec.Error_PostCollinear = evaluateLocalization(unknownPos, estAfter, false);
    rec.Coverage_PostCollinear_pct = coverageFast(estAfter);

    % ---------------- GDOP ----------------
    [rec.MeanGDOP_AllAnchors, rec.MedianGDOP_AllAnchors] = ...
        gdop2DNetworkFast(anchorPos, beforeIdx, unknownPos, hopCount, numAnchors, maxHopCap);
    rec.MeanGDOP_PreCollinear   = rec.MeanGDOP_AllAnchors;
    rec.MedianGDOP_PreCollinear = rec.MedianGDOP_AllAnchors;

    [rec.MeanGDOP_PostCollinear, rec.MedianGDOP_PostCollinear] = ...
        gdop2DNetworkFast(anchorPos, afterIdx, unknownPos, hopCount, numAnchors, maxHopCap);
    [rec.MeanGDOP_MOANS, rec.MedianGDOP_MOANS] = ...
        gdop2DNetworkFast(anchorPos, selM, unknownPos, hopCount, numAnchors, maxHopCap);
    [rec.MeanGDOP_P_Selected, rec.MedianGDOP_P_Selected] = ...
        gdop2DNetworkFast(anchorPos, finalIdxP, unknownPos, hopCount, numAnchors, maxHopCap);

    % ---------------- Direct comparisons ----------------
    rec.Gain_TminusP_m       = eT - eP;
    rec.Gain_MminusP_m       = eM - eP;
    rec.Gain_AllminusP_m     = eAll - eP;
    rec.ErrorChange_PreMinusPostCollinear_m = rec.Error_PreCollinear - rec.Error_PostCollinear;
    rec.GDOPChange_PreMinusPostCollinear    = rec.MeanGDOP_PreCollinear - rec.MeanGDOP_PostCollinear;
    rec.PostCollinearBetterError = double(isfinite(rec.Error_PreCollinear) && ...
        isfinite(rec.Error_PostCollinear) && rec.Error_PostCollinear < rec.Error_PreCollinear);
    rec.ProposedBeatsTraditional = double(isfinite(eP) && isfinite(eT) && eP < eT);
    rec.ProposedBeatsMOANS       = double(isfinite(eP) && isfinite(eM) && eP < eM);
    rec.ProposedBeatsBoth        = double(rec.ProposedBeatsTraditional==1 && rec.ProposedBeatsMOANS==1);
    rec.ProposedUsesFewerAnchorsThanMOANS = double(isfinite(rec.AnchorsUsed_P_Selected) && ...
        isfinite(rec.AnchorsUsed_MOANS) && rec.AnchorsUsed_P_Selected < rec.AnchorsUsed_MOANS);

    rec.Status = "OK";

catch ME
    rec.Status = "FAILED";
    rec.ErrorMessage = string(ME.identifier) + " | " + string(ME.message);
end

rec.TrialWallTime_s = toc(trialWall);
end

%% ========================================================================
function [hopCount, C] = buildAnchorHopGraphFast(allPos, numAnchors, commRange, simParams)
% Build the physical communication graph once, record connectivity, and
% compute shortest-path hops only from anchor rows to all nodes.

N = size(allPos,1);
D = squareform(pdist(allPos));
adj = (D <= commRange);
adj(1:N+1:end) = false;
G = graph(adj);

% ---------------- Physical graph connectivity ----------------
deg = degree(G);
C = struct();
C.PhysicalEdges = numedges(G);
if N > 1
    C.GraphDensity_pct = 100 * (2*C.PhysicalEdges) / (N*(N-1));
else
    C.GraphDensity_pct = NaN;
end
C.MeanNodeDegree = mean(deg);
C.StdNodeDegree  = std(deg);
C.MinNodeDegree  = min(deg);
C.MaxNodeDegree  = max(deg);
C.IsolatedNodes  = sum(deg==0);

bins = conncomp(G);
if isempty(bins)
    C.ConnectedComponents = 0;
    C.LargestComponentNodes = 0;
    C.LargestComponent_pct = NaN;
    C.FullyConnected = 0;
else
    C.ConnectedComponents = max(bins);
    compSizes = accumarray(bins(:),1);
    C.LargestComponentNodes = max(compSizes);
    C.LargestComponent_pct = 100*C.LargestComponentNodes/max(N,1);
    C.FullyConnected = double(C.ConnectedComponents==1);
end

C.MeanAnchorDegree = mean(deg(1:numAnchors));
if numAnchors < N
    C.MeanUnknownDegree = mean(deg(numAnchors+1:end));
else
    C.MeanUnknownDegree = NaN;
end

% A x N shortest-path matrix instead of N x N all-pairs matrix.
hopCount = distances(G, 1:numAnchors);

% Preserve current simulation behavior for drop/noise/cap/integer hops.
if simParams.dropRate > 0
    mask = rand(size(hopCount)) < simParams.dropRate;
    hopCount(mask) = Inf;
end

noiseStd = simParams.noiseStdRange(1) + diff(simParams.noiseStdRange)*rand();
if noiseStd > 0
    hopCount = hopCount + noiseStd * randn(size(hopCount));
    hopCount(hopCount < 0) = 0;
end

hopCount(hopCount > simParams.maxHopCap) = Inf;

if isfield(simParams,'useIntegerHops') && simParams.useIntegerHops
    hopCount = round(hopCount);
    hopCount(hopCount < 0) = 0;
    hopCount(hopCount > simParams.maxHopCap) = Inf;
end

% ---------------- Effective DV-Hop reachability ----------------
if numAnchors < N
    HAU = hopCount(:, numAnchors+1:end);
    usableAU = isfinite(HAU) & HAU >= 1 & HAU <= simParams.maxHopCap;
    C.ReachableAnchorUnknownPairs_pct = 100 * mean(usableAU(:));
    nReachPerUnknown = sum(usableAU,1);
    C.UnknownsReachableFrom3PlusAnchors_pct = 100 * mean(nReachPerUnknown >= 3);
    C.MeanReachableAnchorsPerUnknown = mean(nReachPerUnknown);
    C.MinReachableAnchorsPerUnknown  = min(nReachPerUnknown);
    C.MaxReachableAnchorsPerUnknown  = max(nReachPerUnknown);
    valsAU = HAU(usableAU);
    if isempty(valsAU)
        C.MeanAnchorUnknownHop = NaN;
        C.MedianAnchorUnknownHop = NaN;
    else
        C.MeanAnchorUnknownHop = mean(valsAU);
        C.MedianAnchorUnknownHop = median(valsAU);
    end
else
    C.ReachableAnchorUnknownPairs_pct = NaN;
    C.UnknownsReachableFrom3PlusAnchors_pct = NaN;
    C.MeanReachableAnchorsPerUnknown = NaN;
    C.MinReachableAnchorsPerUnknown = NaN;
    C.MaxReachableAnchorsPerUnknown = NaN;
    C.MeanAnchorUnknownHop = NaN;
    C.MedianAnchorUnknownHop = NaN;
end

HAA = hopCount(:,1:numAnchors);
maskAA = true(numAnchors);
maskAA(1:numAnchors+1:end) = false;
usableAA = isfinite(HAA) & HAA >= 1 & HAA <= simParams.maxHopCap & maskAA;
if numAnchors > 1
    C.AnchorPairReachability_pct = 100 * sum(usableAA(:)) / (numAnchors*(numAnchors-1));
else
    C.AnchorPairReachability_pct = NaN;
end
valsAA = HAA(usableAA);
if isempty(valsAA)
    C.MeanAnchorAnchorHop = NaN;
    C.MedianAnchorAnchorHop = NaN;
else
    C.MeanAnchorAnchorHop = mean(valsAA);
    C.MedianAnchorAnchorHop = median(valsAA);
end
end

%% ========================================================================
function [meanG, medG] = gdop2DNetworkFast(anchorPos, selectedIdx, unknownPos, ...
    hopCount, originalNumAnchors, maxHopCap)
% 2-D geometric dilution of precision evaluated at true unknown positions.
% True positions are used only for post-hoc geometry evaluation and are not
% fed into any localization estimate.

selectedIdx = selectedIdx(:);
U = size(unknownPos,1);
g = inf(U,1);
if numel(selectedIdx) < 3
    meanG = NaN; medG = NaN; return;
end

for u = 1:U
    col = originalNumAnchors + u;
    h = hopCount(selectedIdx, col);
    usable = isfinite(h) & h >= 1 & h <= maxHopCap;
    idx = selectedIdx(usable);
    if numel(idx) < 3, continue; end

    dxy = anchorPos(idx,:) - unknownPos(u,:);
    rr = sqrt(sum(dxy.^2,2));
    good = isfinite(rr) & rr > eps;
    dxy = dxy(good,:);
    rr = rr(good);
    if numel(rr) < 3, continue; end

    H = [dxy(:,1)./rr, dxy(:,2)./rr];
    Q = H' * H;
    if rcond(Q) > 1e-12
        g(u) = sqrt(trace(inv(Q)));
    end
end

finiteG = g(isfinite(g));
if isempty(finiteG)
    meanG = NaN;
    medG  = NaN;
else
    meanG = mean(finiteG);
    medG  = median(finiteG);
end
end

%% ========================================================================
function c = coverageFast(est)
if isempty(est)
    c = NaN;
else
    c = 100 * mean(all(isfinite(est),2));
end
end

function s = idxToStringFast(idx)
idx = idx(:).';
if isempty(idx)
    s = "";
else
    s = string(strjoin(arrayfun(@(x)sprintf('%d',x), idx, 'UniformOutput',false), ';'));
end
end

%% ========================================================================
function rec = makeEmptyFastRecord()
% Fixed fields make this struct safely sliceable in parfor.
rec = struct( ...
    'ComboID',NaN,'AreaSize',NaN,'CommRange',NaN,'TotalNodes',NaN,'AnchorPct',NaN, ...
    'NumAnchors',NaN,'NumUnknowns',NaN,'Trial',NaN,'Seed',NaN,'Status',"",'ErrorMessage',"",'Topology',"", ...
    'NoiseStd',NaN,'MaxHopCap',NaN,'DropRate',NaN,'UseIntegerHops',NaN, ...
    'PhysicalEdges',NaN,'GraphDensity_pct',NaN,'MeanNodeDegree',NaN,'StdNodeDegree',NaN, ...
    'MinNodeDegree',NaN,'MaxNodeDegree',NaN,'IsolatedNodes',NaN,'ConnectedComponents',NaN, ...
    'LargestComponentNodes',NaN,'LargestComponent_pct',NaN,'FullyConnected',NaN, ...
    'MeanAnchorDegree',NaN,'MeanUnknownDegree',NaN, ...
    'ReachableAnchorUnknownPairs_pct',NaN,'UnknownsReachableFrom3PlusAnchors_pct',NaN, ...
    'MeanReachableAnchorsPerUnknown',NaN,'MinReachableAnchorsPerUnknown',NaN,'MaxReachableAnchorsPerUnknown',NaN, ...
    'MeanAnchorUnknownHop',NaN,'MedianAnchorUnknownHop',NaN,'AnchorPairReachability_pct',NaN, ...
    'MeanAnchorAnchorHop',NaN,'MedianAnchorAnchorHop',NaN, ...
    'Error_T',NaN,'Error_M',NaN,'Error_P_Selected',NaN,'Error_P_AllAnchors',NaN, ...
    'Error_PreCollinear',NaN,'Error_PostCollinear',NaN, ...
    'Coverage_T_pct',NaN,'Coverage_M_pct',NaN,'Coverage_P_Selected_pct',NaN, ...
    'Coverage_P_AllAnchors_pct',NaN,'Coverage_PreCollinear_pct',NaN,'Coverage_PostCollinear_pct',NaN, ...
    'AnchorsUsed_MOANS',NaN,'AnchorsUsed_P_Selected',NaN,'AnchorsUsed_P_AllAnchors',NaN, ...
    'Anchors_BeforeCollinear',NaN,'Anchors_AfterCollinear',NaN, ...
    'CollinearRemovedCount',NaN,'CollinearRemovedPct',NaN,'ProposedUsedAllAnchors',NaN, ...
    'SelectedAnchorIDs_MOANS',"",'SelectedAnchorIDs_P',"", ...
    'AnchorIDs_BeforeCollinear',"",'AnchorIDs_AfterCollinear',"", ...
    'MeanGDOP_AllAnchors',NaN,'MedianGDOP_AllAnchors',NaN, ...
    'MeanGDOP_PreCollinear',NaN,'MedianGDOP_PreCollinear',NaN, ...
    'MeanGDOP_PostCollinear',NaN,'MedianGDOP_PostCollinear',NaN, ...
    'MeanGDOP_MOANS',NaN,'MedianGDOP_MOANS',NaN, ...
    'MeanGDOP_P_Selected',NaN,'MedianGDOP_P_Selected',NaN, ...
    'Time_T_s',NaN,'Time_M_s',NaN,'Time_P_Selected_Total_s',NaN, ...
    'Time_P_AllAnchors_s',NaN,'Time_PostCollinear_s',NaN,'TrialWallTime_s',NaN, ...
    'Gain_TminusP_m',NaN,'Gain_MminusP_m',NaN,'Gain_AllminusP_m',NaN, ...
    'ErrorChange_PreMinusPostCollinear_m',NaN,'GDOPChange_PreMinusPostCollinear',NaN, ...
    'PostCollinearBetterError',NaN,'ProposedBeatsTraditional',NaN,'ProposedBeatsMOANS',NaN, ...
    'ProposedBeatsBoth',NaN,'ProposedUsesFewerAnchorsThanMOANS',NaN);
end

%% ========================================================================
function [B, O] = summarizeFastResults(T)
% 90-row by-combo summary: each row aggregates the 100 trials of one combo.
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
B.P_T_vs_P_Selected = splitapply(@pairedPFast,T.Error_T,T.Error_P_Selected,G);
B.P_M_vs_P_Selected = splitapply(@pairedPFast,T.Error_M,T.Error_P_Selected,G);
B.P_Pre_vs_PostCollinear = splitapply(@pairedPFast,T.Error_PreCollinear,T.Error_PostCollinear,G);

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

function p = pairedPFast(a,b)
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

%% =========================================================================
%% ======================== SUBFUNCTION DEFINITIONS ========================
%% =========================================================================
function [ok,covP,robP,errP,csvPath,xlsxPath] = runone( ...
    tag, Top, Trials, IntHops, MaxHop, Noise, flt, m, r, ...
    CommRangeListOverride, AnchorPctListOverride)
% runone  (CSV + Excel)
% Returns:
%   ok,covP,robP,errP : metrics for Proposed
%   csvPath            : per-trial CSV path produced by the sweep
%   xlsxPath           : Excel workbook path (overall/by_combo/per_trial/dictionary)

    % ---------- defaults ----------
    ok       = false;
    covP     = NaN;
    robP     = NaN;
    errP     = Inf;
    csvPath  = '';
    xlsxPath = '';

    % ---------- build sweep args ----------
    baseName = "dvhop_grid_results_ASSISTFREE_" + string(tag);

    AAin = struct('filteringMode',      flt, ...
                  'minAnchorsFrac',     m, ...
                  'rescueAcceptFactor', r);

    args = { ...
        'Topology',           Top, ...
        'TrialsPerCombo',     Trials, ...
        'UseIntegerHops',     logical(IntHops), ...
        'MaxHopCap',          MaxHop, ...
        'NoiseStd',           Noise, ...
        'CSVBaseName',        char(baseName), ...
        'AA',                 AAin ...
    };

    if ~isempty(CommRangeListOverride)
        args = [args, {'CommRangeList', CommRangeListOverride}];
    end
    if ~isempty(AnchorPctListOverride)
        args = [args, {'AnchorPctList', AnchorPctListOverride}];
    end

    % ---------- run sweep (writes: <base>.csv + *_metrics_*.csv) ----------
    csv_s = string(runDVHopGridSweep_AssistantFree_PLUS(args{:}));  % keep as string internally

    % ---------- build Excel workbook (into ./excel_files) ----------
    xlsx_s = "";
    try
        % exportDVHopMetrics50 already writes into ./excel_files next to CSV
        xlsx_s = string(exportDVHopMetrics50(csv_s, 'Topology', string(Top)));
    catch ME
        warning('[runone:%s] Excel export failed: %s', char(tag), ME.message);
    end

    % ---------- try parse metrics from Excel -> Sheet "overall" ----------
    usedExcel = false;
    if xlsx_s~="" && isfile(xlsx_s)
        try
            Tsum = readtable(char(xlsx_s), 'Sheet','overall');
            covP = pickcol(Tsum, {'MeanCoverage_P_pct','MeanLocRatio_P_pct','LocRatio_P_pct','Coverage_P_pct'});
            robP = pickcol(Tsum, {'Robust_P_pct','Robustness_P_pct','Succ_P_pct','Success_P_pct'});
            errP = pickcol(Tsum, {'MeanErr_P','ALE_P','Error_P','Error_Proposed','RMSE_P'});
            usedExcel = all(isfinite([covP,robP,errP]));
        catch ME
            warning('[runone:%s] Could not read Excel sheet "overall": %s', char(tag), ME.message);
        end
    end

    % ---------- fallback: parse *_metrics_overall.csv ----------
    if ~usedExcel
        [folder, baseNoExt, ~] = fileparts(char(csv_s));
        if isempty(folder), folder = '.'; end
        overallCsv = fullfile(folder, [baseNoExt '_metrics_overall.csv']);
        if exist(overallCsv,'file')==2
            try
                Tover = readtable(overallCsv);
                errP = fallbackVal(errP, pickcol(Tover, {'MeanErr_P','ALE_P','Error_P','Error_Proposed','RMSE_P'}));
                covP = fallbackVal(covP, pickcol(Tover, {'MeanCoverage_P_pct','MeanLocRatio_P_pct','LocRatio_P_pct','Coverage_P_pct'}));
                robP = fallbackVal(robP, pickcol(Tover, {'Robust_P_pct','Robustness_P_pct','Succ_P_pct','Success_P_pct'}));
            catch ME
                warning('[runone:%s] Fallback parse of %s failed: %s', char(tag), overallCsv, ME.message);
            end
        end
    end

    % ---------- last resort: compute from raw per-trial CSV ----------
    if ~all(isfinite([errP, covP, robP]))
        try
            Traw = readtable(char(csv_s));

            if ~isfinite(errP)
                if ismember('Error_P', Traw.Properties.VariableNames)
                    errP = mean(Traw.Error_P, 'omitnan');
                elseif ismember('Error_Proposed', Traw.Properties.VariableNames)
                    errP = mean(Traw.Error_Proposed, 'omitnan');
                end
            end

            if ~isfinite(covP)
                if ismember('FracLoc_P', Traw.Properties.VariableNames)
                    covP = 100 * mean(Traw.FracLoc_P, 'omitnan');
                elseif all(ismember({'NumLoc_P','NumUnknowns'}, Traw.Properties.VariableNames))
                    covP = 100 * mean(Traw.NumLoc_P ./ max(Traw.NumUnknowns,1), 'omitnan');
                elseif ismember('LocRatio_P_pct', Traw.Properties.VariableNames)
                    covP = mean(Traw.LocRatio_P_pct, 'omitnan');
                end
            end

            if ~isfinite(robP)
                if ismember('Succ_Proposed', Traw.Properties.VariableNames)
                    robP = 100 * mean(logical(Traw.Succ_Proposed), 'omitnan');
                else
                    e = NaN(height(Traw),1);
                    if ismember('Error_P', Traw.Properties.VariableNames), e = Traw.Error_P; end
                    if all(~isfinite(e)) && ismember('Error_Proposed', Traw.Properties.VariableNames)
                        e = Traw.Error_Proposed;
                    end
                    robP = 100 * mean(isfinite(e));
                end
            end
        catch ME
            warning('[runone:%s] Raw CSV parse failed (%s).', char(tag), ME.message);
        end
    end

    % success if all finite
    ok = all(isfinite([errP, covP, robP]));

    % ---------- outputs as char (to match your new function style) ----------
    csvPath  = char(csv_s);
    xlsxPath = char(xlsx_s);

    % ===== helpers =====
    function v = fallbackVal(oldv, newv)
        if isfinite(oldv), v = oldv; else, v = newv; end
    end

    function val = pickcol(TT, names)
        % Return first scalar numeric from candidate column names (or NaN).
        val = NaN;
        if isempty(TT) || height(TT) < 1, return; end
        for k = 1:numel(names)
            nm = names{k};
            if ismember(nm, TT.Properties.VariableNames)
                v = TT.(nm);
                if isempty(v), continue; end
                if iscellstr(v) || isstring(v), v = str2double(string(v)); end
                try
                    x = v(1);
                    if isnumeric(x) && isfinite(x)
                        val = x;
                        return;
                    end
                catch
                end
            end
        end
    end
end



% ======================= local helper =======================
function val = pickcol(TT, names)
% Safely pick the first available numeric column name from list "names".
% Returns scalar (first row) or NaN if not found/empty/non-numeric.
    val = NaN;
    if isempty(TT) || height(TT) < 1, return; end
    for k = 1:numel(names)
        nm = names{k};
        if ismember(nm, TT.Properties.VariableNames)
            v = TT.(nm);
            if ~isempty(v)
                % If string/cellstr, try to convert; else take numeric
                if iscellstr(v) || isstring(v)
                    v = str2double(string(v));
                end
                try
                    v1 = v(1);
                    if isnumeric(v1) && isfinite(v1)
                        val = v1;
                        return;
                    end
                catch
                    % ignore and continue
                end
            end
        end
    end
end



% ======================= local helpers =======================






function s = tern(cond,a,b)
% simple ternary helper
    if cond, s=a; else, s=b; end
end


%% =========================================================================
%% ================== SWEEP FUNCTION: runDVHopGridSweep_AssistantFree_PLUS
%% =========================================================================
function csvPath = runDVHopGridSweep_AssistantFree_PLUS(varargin)
% runDVHopGridSweep_AssistantFree_PLUS
%
% Sweep (AreaSize, CommRange, TotalNodes, AnchorPct) combos and compare:
%   1. Traditional DV-Hop
%   2. MOANS-style DV-Hop
%   3. Proposed (our selection+enrichment+rescue+rollback safety)
%
% We log per-trial metrics to:
%   <base>.csv
%
% Then we later summarize into:
%   <base>_metrics_byCombo.csv
%   <base>_metrics_overall.csv
%
% Name-Value inputs (REAL fine-tune defaults):
%   'AreaList'        [100]
%   'CommRangeList'   [30 35 40]         (REAL setting in fine-tune)
%   'TotalNodesList'  [100]
%   'AnchorPctList'   [10 15 20 25 30]
%   'TrialsPerCombo'  3
%   'TolMeters'       5
%   'TolFracOfRange'  0.20
%   'CostWeights'     struct('time',1,'anchors',0)
%   'CSVBaseName'     'dvhop_grid_results_ASSISTFREE'
%   'DropRate'        0
%   'NoiseStd'        0.01
%   'MaxHopCap'       8
%   'UseIntegerHops'  true    (INTEGER hops only, enforced)
%   'AA'              struct('filteringMode','moderate', 'minAnchorsFrac',0.7, 'rescueAcceptFactor',1.3)
%   'Topology'        'C-Shape'
%
% Output:
%   csvPath  (string): path to per-trial CSV (which we keep under ./excel_files)

% ---------- Parse inputs ----------
ip = inputParser;
addParameter(ip,'AreaList',[100],@isnumeric);

%%% FIX#1: REAL env defaults for fine-tune runs (when overrides empty)
addParameter(ip,'CommRangeList',[30 35 40],@isnumeric);
addParameter(ip,'TotalNodesList',[100],@isnumeric);
addParameter(ip,'AnchorPctList',[10 15 20 25 30],@isnumeric);
addParameter(ip,'TrialsPerCombo',3,@(x)isnumeric(x)&&isscalar(x)&&x>=1);

addParameter(ip,'TolMeters',5,@(x)isnumeric(x)&&isscalar(x)&&x>=0);
addParameter(ip,'TolFracOfRange',0.20,@(x)isnumeric(x)&&isscalar(x)&&x>=0);
addParameter(ip,'CostWeights',struct('time',1,'anchors',0),@isstruct);
addParameter(ip,'CSVBaseName','dvhop_grid_results_ASSISTFREE',@(s)ischar(s)||isstring(s));
addParameter(ip,'DropRate',0,@(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<=1);
addParameter(ip,'NoiseStd',0.01,@(x)isnumeric(x)&&isscalar(x)&&x>=0);
addParameter(ip,'MaxHopCap',8,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(ip,'UseIntegerHops',true,@islogical);
addParameter(ip,'AA',struct(),@isstruct);
addParameter(ip,'Topology','C-Shape',@(s)ischar(s)||isstring(s));
parse(ip,varargin{:});

topologyTag = string(ip.Results.Topology);

AreaList       = ip.Results.AreaList(:)';
CommRangeList  = ip.Results.CommRangeList(:)';
TotalNodesList = ip.Results.TotalNodesList(:)';
AnchorPctList  = ip.Results.AnchorPctList(:)';
TrialsPerCombo = ip.Results.TrialsPerCombo;
TolMeters      = ip.Results.TolMeters;
TolFrac        = ip.Results.TolFracOfRange;
W              = ip.Results.CostWeights;
if ~isfield(W,'time'),    W.time = 1; end
if ~isfield(W,'anchors'), W.anchors = 0; end
baseName       = char(ip.Results.CSVBaseName);

% ---------- Guard required subfunctions ----------
mustHave = {'buildHopGraph','runTraditionalDVHop','runMOANSDVHop','runProposed_Enriched'};
for k = 1:numel(mustHave)
    assert(exist(mustHave{k},'file')==2 || exist(mustHave{k},'file')==6, ...
        'Missing %s on path.', mustHave{k});
end

% ---------- Sim params ----------
simParams.dropRate       = ip.Results.DropRate;
simParams.noiseStdRange  = [ip.Results.NoiseStd ip.Results.NoiseStd];
simParams.maxHopCap      = ip.Results.MaxHopCap;
simParams.useIntegerHops = ip.Results.UseIntegerHops;  % integer hops only

% ---------- Anchor Assist (AA) policy defaults ----------
AA = struct('filteringMode','soft','minAnchorsFrac',0.55,'rescueAcceptFactor',1.35);
AA = mergeStructs(AA, ip.Results.AA);

% ---------- Output CSV prep in ./excel_files ----------
[baseFolder, baseFileNoExt, ~] = fileparts(baseName);
if isempty(baseFolder)
    baseFolder = '.';
end
excelDir = fullfile(baseFolder, 'excel_files');
if ~exist(excelDir, 'dir')
    mkdir(excelDir);
end

csvPath = fullfile(excelDir, [baseFileNoExt '.csv']);
if exist(csvPath,'file')
    delete(csvPath);
end

% Columns we will log per trial
varNames = { ...
 'AreaSize','CommRange','TotalNodes','AnchorPct','NumAnchors','AnchorRatio','NumUnknowns', ...
 'Trial','Seed', ...
 'AnchorsUsed_MOANS','AnchorsUsed_Proposed', ...
 'NumLoc_T','NumLoc_M','NumLoc_P', ...
 'FracLoc_T','FracLoc_M','FracLoc_P', ...
 'Error_T','Error_M','Error_P_raw','Error_P', ...
 'NRMSE_R_T','NRMSE_R_M','NRMSE_R_P', ...
 'NRMSE_L_T','NRMSE_L_M','NRMSE_L_P', ...
 'MedianErr_T','MedianErr_M','MedianErr_P', ...
 'P90_T','P90_M','P90_P','P95_T','P95_M','P95_P', ...
 'MAE_X_P','MAE_Y_P','Bias_X_P','Bias_Y_P', ...
 'Msgs_Total','Msgs_perNode','Msgs_perLoc','Bytes_perNode','FloodRebroadcasts', ...
 'Energy_TX','Energy_RX','Energy_perNode','Energy_perLoc', ...
 'Time_T_s','Time_M_s','Time_P_s','Runtime_perNode_s','Complexity_LS','Memory_perNode_B', ...
 'Iter_toConv','ConvSuccess_pct', ...
 'Succ_Traditional','Succ_MOANS','Succ_Proposed', ...
 'Gain_TminusP_m','Gain_TminusM_m','Gain_MminusP_m', ...
 'AccAbs_P','AccRel_P','NodeHitAbs_P','NodeHitRel_P', ...
 'Cost_P','PASS0_Skipped','Topology'};

rowCount = 0;
t0 = tic;

%%% FIX#2: headless-safe preview flag computed ONCE (and reused)
%%SHOW_PREVIEW  = usejava('jvm') && ~strcmpi(get(0,'DefaultFigureVisible'),'off');
SHOW_PREVIEW  = usejava('jvm');
oPreviewShown = false;

% ==================== SWEEP LOOPS ====================
for ai = 1:numel(AreaList)
    areaSize = AreaList(ai);

    for ci = 1:numel(CommRangeList)
        commRange = CommRangeList(ci);

        for ni = 1:numel(TotalNodesList)
            N = TotalNodesList(ni);

            for pi = 1:numel(AnchorPctList)
                pct = AnchorPctList(pi);

                % determine anchor / unknown counts
                numAnchors  = max(3, round(N * pct/100));
                numAnchors  = min(numAnchors, N-3);
                numUnknowns = N - numAnchors;
                if numUnknowns < 3
                    dvprint('Skip A=%g, R=%g, N=%d, pct=%g (too few unknowns)\n', areaSize, commRange, N, pct);
                    continue;
                end
                anchorRatio = numAnchors / N;

for t = 1:TrialsPerCombo
    % unique-ish seed per combo/rep
    seed = uint32(1e6*ai + 1e4*ci + 1e2*ni + 10*pi + t);
    rng(seed,'twister');

    % --- propagate seed to simParams ---
    simParams.seed = double(seed);           % many functions expect this
    try
        simParams.randStream = RandStream('mt19937ar','Seed', double(seed));
    catch
    end

    dvprint('\n=== COMBO A=%g R=%g N=%d pct=%g | Trial %d (seed %d) ===\n', ...
        areaSize, commRange, N, pct, t, seed);
    dvprint('    NumAnchors=%d  NumUnknowns=%d  AnchorRatio=%.3f\n', ...
        numAnchors, numUnknowns, anchorRatio);

    % ------ DEPLOYMENT (C-Shape with hole) ------
    innerRadius = 0.20 * areaSize;
    anchorPos   = generateOShapePositions(numAnchors,  areaSize, areaSize, innerRadius);
    unknownPos  = generateOShapePositions(numUnknowns, areaSize, areaSize, innerRadius);
    allPos      = [anchorPos; unknownPos];

    % ------ preview only once (headless-safe; uses flags set earlier) ------
 % ------ preview only once (headless-safe; temporarily enable figures) ------
if SHOW_PREVIEW && ~oPreviewShown
    try
        defVis = get(0,'DefaultFigureVisible');
        set(0,'DefaultFigureVisible','on');             % allow the one preview to display
        [~, ~] = previewOShapeTopology(areaSize, anchorPos, unknownPos, innerRadius);
        drawnow;
        set(0,'DefaultFigureVisible', defVis);          % restore whatever it was (likely 'off')
    catch ME
        warning('Skipping preview (graphics not available): %s', ME.message);
    end
    oPreviewShown = true;                               % never show again this run
end


    % ------ Connectivity / hop graph (INTEGER hops enforced) ------
    [hopCount, adjMatrix] = buildHopGraph(allPos, commRange, simParams);

    % ------ Traditional DV-Hop ------
    tic;
    [eTrad, estTrad] = runTraditionalDVHop(anchorPos, unknownPos, allPos, ...
        hopCount, adjMatrix, commRange, areaSize, simParams);
    timeTrad   = toc;

    numLocTrad  = sum(all(isfinite(estTrad),2));
    fracLocTrad = numLocTrad / max(numUnknowns,1);

    eNode_T    = rownorm(estTrad - unknownPos);
    medT       = median_s(eNode_T);
    [p90T,p95T]= pctiles_s(eNode_T);
    NRMSE_R_T  = mean_s(eNode_T)/commRange;
    NRMSE_L_T  = mean_s(eNode_T)/areaSize;

    dvprint('  Traditional:\n');
    dvprint('    Error_T           = %.3f m (mean)\n', eTrad);
    dvprint('    MedianErr_T       = %.3f m | P90_T=%.3f | P95_T=%.3f\n', medT, p90T, p95T);
    dvprint('    NRMSE_R_T         = %.4f | NRMSE_L_T = %.4f\n', NRMSE_R_T, NRMSE_L_T);
    dvprint('    Coverage_T        = %d/%d (%.1f%% localized)\n', ...
        numLocTrad, numUnknowns, 100*fracLocTrad);
    dvprint('    Time_T_s          = %.6f s\n', timeTrad);

    % ------ MOANS baseline ------
    tic;
    [eMOAN, estMOAN, selMOAN] = runMOANSDVHop(anchorPos, unknownPos, allPos, ...
        hopCount, adjMatrix, commRange, areaSize, simParams);
    timeMOAN   = toc;

    numLocMOAN  = sum(all(isfinite(estMOAN),2));
    fracLocMOAN = numLocMOAN / max(numUnknowns,1);
    nUsedMOAN   = numel(selMOAN);

    eNode_M    = rownorm(estMOAN - unknownPos);
    medM       = median_s(eNode_M);
    [p90M,p95M]= pctiles_s(eNode_M);
    NRMSE_R_M  = mean_s(eNode_M)/commRange;
    NRMSE_L_M  = mean_s(eNode_M)/areaSize;

    dvprint('  MOANS:\n');
    dvprint('    Error_M           = %.3f m (mean)\n', eMOAN);
    dvprint('    MedianErr_M       = %.3f m | P90_M=%.3f | P95_M=%.3f\n', medM, p90M, p95M);
    dvprint('    NRMSE_R_M         = %.4f | NRMSE_L_M = %.4f\n', NRMSE_R_M, NRMSE_L_M);
    dvprint('    Coverage_M        = %d/%d (%.1f%% localized)\n', ...
        numLocMOAN, numUnknowns, 100*fracLocMOAN);
    dvprint('    AnchorsUsed_M     = %d\n', nUsedMOAN);
    dvprint('    Time_M_s          = %.6f s\n', timeMOAN);

    % ------ Proposed (subset + enrichment + rescue + rollback safety) ------
    fullIdxAllAnchors = (1:numAnchors).';
    fullPosAllAnchors = anchorPos;
    rolledBackToTraditional = false; %#ok<NASGU>

    tic;
[errProp, estProp, nUsedProp, finalIdxProp] = runProposed_Enriched( ...
    anchorPos, unknownPos, allPos, ...
    hopCount, adjMatrix, ...
    commRange, areaSize, ...
    simParams, AA, ...
    eTrad, eMOAN);   % <- pass baseline errors
timeProp = toc;

    % Map new outputs into legacy columns:
    eProp_raw    = errProp;   % goes to Error_P_raw column
    eProp        = errProp;   % goes to Error_P column
    estPropEff   = estProp;   % final coordinate estimates we "ship"
    pass0Skipped = false;     % legacy safety flag (always false now)
    rolledBack   = false;     % never rolled back now

    % Coverage accounting:
    if pass0Skipped || rolledBack
        numLocProp  = numLocTrad;
        fracLocProp = fracLocTrad;
        if ~any(isfinite(estPropEff(:)))
            estPropEff = estTrad;
        end
    else
        numLocProp  = sum(all(isfinite(estPropEff),2));
        fracLocProp = numLocProp / max(numUnknowns,1);
    end

    % Compute per-node stats for Proposed using estPropEff
    eNode_P     = rownorm(estPropEff - unknownPos);
    medP        = median_s(eNode_P);
    [p90P,p95P] = pctiles_s(eNode_P);
    NRMSE_R_P   = mean_s(eNode_P)/commRange;
    NRMSE_L_P   = mean_s(eNode_P)/areaSize;

    [mae_xP, mae_yP, bxP, byP] = axis_stats(estPropEff, unknownPos);

    % Success flags
    succTrad = isfinite(eTrad);
    succMOAN = isfinite(eMOAN);
    succProp = isfinite(eProp);

    % Accuracy-at-thresholds for Proposed
    [~, ~, nodeHitAbs, nodeHitRel] = nodeAccuracy_local( ...
        unknownPos, estPropEff, commRange, TolMeters, TolFrac);
    accAbs   = succProp && (eProp <= TolMeters);
    accRel   = succProp && (eProp <= TolFrac * commRange);

    % Improvements and runtime comparisons
    impVsTrad = rel_improve(eTrad, eProp); %#ok<NASGU>
    impVsMOAN = rel_improve(eMOAN, eProp); %#ok<NASGU>
    spdVsTrad = ratio_safe(timeTrad, timeProp); %#ok<NASGU>
    spdVsMOAN = ratio_safe(timeMOAN, timeProp); %#ok<NASGU>

    % Simple "cost" metric combining runtime + anchors
    costProp = W.time * timeProp + W.anchors * (nUsedProp / N);

    % Network/energy placeholders
    msgsTot        = NaN;
    msgsPerNode    = NaN;
    msgsPerLoc     = NaN;
    bytesPerNode   = NaN;
    rebcasts       = NaN;
    eTX            = NaN;
    eRX            = NaN;
    ePerNode       = NaN;
    ePerLoc        = NaN;
    runtimePerNode = timeProp / max(numUnknowns,1);

    % Gains (lower error means better)
    gain_TmP = eTrad - eProp;   % Trad  - Proposed
    gain_TmM = eTrad - eMOAN;   % Trad  - MOANS
    gain_MmP = eMOAN - eProp;   % MOANS - Proposed

    dvprint('  Proposed:\n');
    dvprint('    Error_P(raw/final)= %.3f m\n', eProp);
    dvprint('    MedianErr_P       = %.3f m | P90_P=%.3f | P95_P=%.3f\n', medP, p90P, p95P);
    dvprint('    NRMSE_R_P         = %.4f | NRMSE_L_P = %.4f\n', NRMSE_R_P, NRMSE_L_P);
    dvprint('    Coverage_P        = %d/%d (%.1f%% localized)\n', ...
        numLocProp, numUnknowns, 100*fracLocProp);
    dvprint('    AnchorsUsed_P     = %d\n', nUsedProp);
    dvprint('    Time_P_s          = %.6f s\n', timeProp);
    dvprint('    Bias_X_P / Bias_Y_P = %.4f / %.4f\n', bxP, byP);
    dvprint('    MAE_X_P / MAE_Y_P   = %.4f / %.4f\n', mae_xP, mae_yP);
    dvprint('    Hit@Abs<=%.2fm     = %.1f%% of nodes\n', TolMeters, nodeHitAbs);
    dvprint('    Hit@Rel<=%.0f%%R   = %.1f%% of nodes\n', 100*TolFrac, nodeHitRel);

    % --- console: compare all 3 on this trial ---
    bestErrVal = min([eTrad, eMOAN, eProp]);
    if abs(bestErrVal - eTrad) < 1e-9
        bestTag = 'Traditional';
    elseif abs(bestErrVal - eMOAN) < 1e-9
        bestTag = 'MOANS';
    else
        bestTag = 'Proposed';
    end
    dvprint('  ⇒ BEST THIS TRIAL: %s (%.3f m)\n', bestTag, bestErrVal);
    dvprint('    Gains: (Trad-Prop)=%.3f m | (MOANS-Prop)=%.3f m | (Trad-MOANS)=%.3f m\n', ...
        gain_TmP, gain_MmP, gain_TmM);

    % ----- Row to append -----
    row = table( ...
        areaSize, commRange, N, pct, numAnchors, anchorRatio, numUnknowns, ...
        t, seed, ...
        nUsedMOAN, nUsedProp, ...
        numLocTrad, numLocMOAN, numLocProp, ...
        fracLocTrad, fracLocMOAN, fracLocProp, ...
        eTrad, eMOAN, eProp_raw, eProp, ...
        NRMSE_R_T, NRMSE_R_M, NRMSE_R_P, ...
        NRMSE_L_T, NRMSE_L_M, NRMSE_L_P, ...
        medT, medM, medP, ...
        p90T, p90M, p90P, p95T, p95M, p95P, ...
        mae_xP, mae_yP, bxP, byP, ...
        msgsTot, msgsPerNode, msgsPerLoc, bytesPerNode, rebcasts, ...
        eTX, eRX, ePerNode, ePerLoc, ...
        timeTrad, timeMOAN, timeProp, runtimePerNode, "O(m^3) LS", NaN, ...
        NaN, NaN, ...                        % Iter_toConv, ConvSuccess_pct
        succTrad, succMOAN, succProp, ...    % Succ_Traditional / MOANS / Proposed
        gain_TmP, gain_TmM, gain_MmP, ...
        double(accAbs), double(accRel), nodeHitAbs, nodeHitRel, ...
        costProp, logical(pass0Skipped), ...
        topologyTag, ...
        'VariableNames', varNames);

    % write (append) row
    if ~exist(csvPath,'file')
        writetable(row, csvPath);
        dvprint('  [LOG] wrote first row to %s\n', csvPath);
    else
        writetable(row, csvPath, 'WriteMode','append');
        dvprint('  [LOG] appended row %d to %s\n', rowCount+1, csvPath);
    end
    rowCount = rowCount + 1;

end % TrialsPerCombo

            end % AnchorPctList
        end % TotalNodesList
    end % CommRangeList
end % AreaList

dvprint('✅ Sweeps finished: %d rows → %s (%.1fs)\n', rowCount, csvPath, toc(t0));

% ==================== Summaries ====================
T = readtable(csvPath);
[ByCombo, Overall] = summarize_by_combo_overall(T, TrialsPerCombo, TolMeters, TolFrac, W);

[folder,base,~] = fileparts(csvPath); if isempty(folder), folder='.'; end
writetable(ByCombo, fullfile(folder,[base '_metrics_byCombo.csv']));
writetable(Overall, fullfile(folder,[base '_metrics_overall.csv']));
dvprint('📝 Wrote:\n  • %s\n  • %s\n', ...
    fullfile(folder,[base '_metrics_byCombo.csv']), ...
    fullfile(folder,[base '_metrics_overall.csv']));

end % runDVHopGridSweep_AssistantFree_PLUS


%% =========================================================================
%% ============================= TOPOLOGY UTILS ============================
%% =========================================================================

function positions = generateOShapePositions(numPositions, areaWidth, areaHeight, ~)
% Adapter: keep old name/signature but generate a C-shape (no circular hole)
% The "C" is made of top & bottom horizontal bands and a left vertical band.
    cWidth = 0.25 * min(areaWidth, areaHeight);   % thickness of the "C" arms (tweak 0.12–0.25)
    positions = generateCShapePositions(numPositions, areaWidth, areaHeight, cWidth);
end


function [anchorPoss, unknownPoss] = previewOShapeTopology(areaSize, anchorPos_in, unknownPos_in, ~)
% Preview (one-time) for the C-shape topology — opening on the RIGHT.

    persistent hasShown;
    if isempty(hasShown), hasShown = false; end

    cWidth = 0.18 * areaSize;  % same thickness used for preview generation

    % anchors
    if isscalar(anchorPos_in)
        anchorPoss = generateCShapePositions(anchorPos_in,  areaSize, areaSize, cWidth);
    else
        validateattributes(anchorPos_in, {'numeric'},{'2d','ncols',2});
        anchorPoss = anchorPos_in;
    end

    % unknowns
    if isscalar(unknownPos_in)
        unknownPoss = generateCShapePositions(unknownPos_in, areaSize, areaSize, cWidth);
    else
        validateattributes(unknownPos_in, {'numeric'},{'2d','ncols',2});
        unknownPoss = unknownPos_in;
    end

    % plot only once
    if ~hasShown
        figure('Color','w'); hold on; box on; grid on;
        scatter(anchorPoss(:,1),  anchorPoss(:,2), 36, 'r', 'filled', 'DisplayName','Anchors');
        scatter(unknownPoss(:,1), unknownPoss(:,2), 20, 'b',          'DisplayName','Unknowns');
        plot([0 areaSize areaSize 0 0], [0 0 areaSize areaSize 0], 'k-','LineWidth',1);
        axis equal; xlim([0 areaSize]); ylim([0 areaSize]);
        title(sprintf('C-shape topology (thickness = %.2f, area = %dx%d)', cWidth, areaSize, areaSize));
        xlabel('X'); ylabel('Y'); legend('Location','bestoutside');
        drawnow;
        hasShown = true;
    end
end


function positions = generateCShapePositions(numPositions, areaWidth, areaHeight, cWidth)
% Sample uniformly in the square, keep points that lie in the "C" band:
%   - top band:    y >= areaHeight - cWidth
%   - bottom band: y <= cWidth
%   - left band:   x <= cWidth
% Opening is on the RIGHT side (no right vertical band).

    positions = zeros(0,2);
    batch = max(200, 4*numPositions);  % batched rejection for speed

    while size(positions,1) < numPositions
        x = rand(batch,1) * areaWidth;
        y = rand(batch,1) * areaHeight;

        valid = (y >= areaHeight - cWidth) | (y <= cWidth) | (x <= cWidth);
        if any(valid)
            newPts = [x(valid), y(valid)];
            need = numPositions - size(positions,1);
            positions = [positions; newPts(1:min(need, size(newPts,1)), :)]; %#ok<AGROW>
        end
    end
end


%% =========================================================================
%% ======================== EXPORT METRICS TO EXCEL ========================
%% =========================================================================

function xlsxPath = exportDVHopMetrics50(csvPath, varargin)
% exportDVHopMetrics50 (robust to string/char)
% - Forces char for all filenames and 'Topology' arg.
% - Uses sprintf for filename building (avoids [] with strings).
% - Always writes Excel into ./excel_files.

ip = inputParser;
addParameter(ip,'CommRangeFromCSV',true,@islogical);
addParameter(ip,'CommRange',[],@(x) isempty(x) || (isnumeric(x)&&isscalar(x)&&x>0));
addParameter(ip,'SideLength',[],@(x) isempty(x) || (isnumeric(x)&&isscalar(x)&&x>0));
addParameter(ip,'ExcelBase','dvhop_metrics_50',@(s)ischar(s)||isstring(s));
addParameter(ip,'Topology','',@(s)ischar(s)||isstring(s));
addParameter(ip,'GroupByTopology',false,@islogical);
parse(ip,varargin{:});

useCRfromCSV = ip.Results.CommRangeFromCSV;
R_override   = ip.Results.CommRange;
L_override   = ip.Results.SideLength;

% ---- normalize to char early (prevents [] concat errors) ----
base        = char(ip.Results.ExcelBase);
topologyTag = char(string(ip.Results.Topology));  % char scalar
groupByTopo = ip.Results.GroupByTopology;

% ---- read raw trials ----
if ~isfile(csvPath)
    error('File not found: %s', char(csvPath));
end
T = readtable(char(csvPath));

% If no explicit topology provided, infer (as char)
if isempty(topologyTag)
    if ismember('Topology', T.Properties.VariableNames)
        u = unique(string(T.Topology));
        if numel(u)==1
            topologyTag = char(u);
        else
            topologyTag = 'mixed';
        end
    else
        topologyTag = 'unknown';
    end
end


% ---- build args for compute (all name/vals are char-safe) ----
args = { ...
    'CommRangeFromCSV', useCRfromCSV, ...
    'Topology',         topologyTag, ...
    'GroupByTopology',  groupByTopo};

if ~isempty(R_override)
    args(end+1:end+2) = {'CommRange', R_override};
end
if ~isempty(L_override)
    args(end+1:end+2) = {'SideLength', L_override};
end

% ---- compute summaries ----
[TrialMetrics, ByCombo, Overall, Dict] = computeDVHopMetrics50(T, args{:});

% ---- output paths (always under ./excel_files next to CSV) ----
[folder, baseName, ~] = fileparts(char(csvPath));
if isempty(folder), folder = '.'; end

excelDir = fullfile(folder, 'excel_files');
if ~exist(excelDir, 'dir'), mkdir(excelDir); end

xlsxFile = sprintf('%s_%s.xlsx', base, baseName);   % avoids [] concat issues
xlsxPath = fullfile(excelDir, xlsxFile);

if isfile(xlsxPath), delete(xlsxPath); end

% ---- write sheets ----
writetable(TrialMetrics, xlsxPath, 'Sheet','per_trial');
writetable(ByCombo,      xlsxPath, 'Sheet','by_combo');
writetable(Overall,      xlsxPath, 'Sheet','overall');
writetable(Dict,         xlsxPath, 'Sheet','dictionary');

dvprint('📘 Wrote Excel metrics to: %s\n', xlsxPath);
end



%% =========================================================================
%% ===================== METRICS SUMMARY / COMBOS ETC ======================
%% =========================================================================

function [ByCombo, Overall] = summarize_by_combo_overall(T, TrialsPerCombo, TolMeters, TolFrac, W)
% Build by-combo & overall summary tables from raw per-trial CSV

if nargin<2 || isempty(TrialsPerCombo), TrialsPerCombo = NaN; end
if nargin<3 || isempty(TolMeters),      TolMeters      = NaN; end
if nargin<4 || isempty(TolFrac),        TolFrac        = NaN; end
if nargin<5 || isempty(W),              W              = struct('time',NaN,'anchors',NaN); end

topologyTag = "unknown";
if ismember('Topology', T.Properties.VariableNames)
    u = unique(string(T.Topology));
    if numel(u) == 1
        topologyTag = u;
    else
        topologyTag = "mixed";
    end
end


groupVars = {'AreaSize','CommRange','TotalNodes','AnchorPct','NumAnchors','NumUnknowns'};
if ismember('Topology', T.Properties.VariableNames)
    groupVars = [groupVars, {'Topology'}];
end

[G, Key] = findgroups(T(:,groupVars));
agg     = @(x) mean(x,'omitnan');
agg_med = @(x) median(x,'omitnan');
agg_sd  = @(x) std(x,'omitnan');
isfin   = @(x) mean(isfinite(x));

ByCombo = Key;
ByCombo.Trials = splitapply(@numel, T.Trial, G);

ByCombo.MeanErr_T  = splitapply(agg,     T.Error_T, G);
ByCombo.MedErr_T   = splitapply(agg_med, T.Error_T, G);
ByCombo.StdErr_T   = splitapply(agg_sd,  T.Error_T, G);
ByCombo.MeanErr_M  = splitapply(agg,     T.Error_M, G);
ByCombo.MedErr_M   = splitapply(agg_med, T.Error_M, G);
ByCombo.StdErr_M   = splitapply(agg_sd,  T.Error_M, G);
ByCombo.MeanErr_P  = splitapply(agg,     T.Error_P, G);
ByCombo.MedErr_P   = splitapply(agg_med, T.Error_P, G);
ByCombo.StdErr_P   = splitapply(agg_sd,  T.Error_P, G);

ByCombo.NRMSE_R_P  = splitapply(agg, T.NRMSE_R_P, G);
ByCombo.NRMSE_L_P  = splitapply(agg, T.NRMSE_L_P, G);

ByCombo.LocRatio_T_pct = 100*splitapply(agg, T.FracLoc_T, G);
ByCombo.LocRatio_M_pct = 100*splitapply(agg, T.FracLoc_M, G);
ByCombo.LocRatio_P_pct = 100*splitapply(agg, T.FracLoc_P, G);

ByCombo.Robust_T_pct = 100*splitapply(isfin, T.Error_T, G);
ByCombo.Robust_M_pct = 100*splitapply(isfin, T.Error_M, G);
ByCombo.Robust_P_pct = 100*splitapply(isfin, T.Error_P, G);

ByCombo.Time_T_s = splitapply(agg, T.Time_T_s, G);
ByCombo.Time_M_s = splitapply(agg, T.Time_M_s, G);
ByCombo.Time_P_s = splitapply(agg, T.Time_P_s, G);


[ByCombo.Diff_TminusP_mean, ByCombo.CI_TminusP_low, ByCombo.CI_TminusP_high, ByCombo.P_TminusP] = ...
    pairedComboStats_LOCAL(T, G, 'Error_T', 'Error_P');
[ByCombo.Diff_MminusP_mean, ByCombo.CI_MminusP_low, ByCombo.CI_MminusP_high, ByCombo.P_MminusP] = ...
    pairedComboStats_LOCAL(T, G, 'Error_M', 'Error_P');

% Slopes per block
blkG = findgroups(ByCombo(:,{'AreaSize','CommRange','TotalNodes'}));
sE = nan(height(ByCombo),1); sL = nan(height(ByCombo),1);
K  = max(blkG);
for b = 1:K
    idx = (blkG==b);
    x = ByCombo.AnchorPct(idx);
    yE = ByCombo.MeanErr_P(idx);
    yL = ByCombo.LocRatio_P_pct(idx);
    sE(idx) = slope1d_LOCAL(x, yE);
    sL(idx) = slope1d_LOCAL(x, yL);
end
ByCombo.Slope_ALE_vs_AnchorPct_P = sE;
ByCombo.Slope_Loc_vs_AnchorPct_P = sL;

% --- NEW: Anchors used stats into quick CSV by_combo ---
if ismember('AnchorsUsed_MOANS', T.Properties.VariableNames)
    ByCombo.AnchorsUsed_M_mean = splitapply(agg,     T.AnchorsUsed_MOANS, G);
    ByCombo.AnchorsUsed_M_med  = splitapply(agg_med, T.AnchorsUsed_MOANS, G);
    ByCombo.AnchorsUsed_M_std  = splitapply(agg_sd,  T.AnchorsUsed_MOANS, G);
end
if ismember('AnchorsUsed_Proposed', T.Properties.VariableNames)
    ByCombo.AnchorsUsed_P_mean = splitapply(agg,     T.AnchorsUsed_Proposed, G);
    ByCombo.AnchorsUsed_P_med  = splitapply(agg_med, T.AnchorsUsed_Proposed, G);
    ByCombo.AnchorsUsed_P_std  = splitapply(agg_sd,  T.AnchorsUsed_Proposed, G);
end

if ~ismember('Topology', ByCombo.Properties.VariableNames)
    ByCombo.Topology = repmat(topologyTag, height(ByCombo), 1);
else
    ByCombo.Topology = string(ByCombo.Topology);
end

% ---------------- overall ----------------
Overall = table;
Overall.TotalTrials           = height(T);
Overall.TrialsPerCombo        = TrialsPerCombo;
Overall.TolMeters             = TolMeters;
Overall.TolFracOfRange        = TolFrac;
Overall.Cost_w_time           = local_get(W,'time',NaN);
Overall.Cost_w_anchors        = local_get(W,'anchors',NaN);

Overall.MeanErr_T             = mean(T.Error_T,'omitnan');
Overall.MeanErr_M             = mean(T.Error_M,'omitnan');
Overall.MeanErr_P             = mean(T.Error_P,'omitnan');

Overall.NRMSE_R_P             = mean(T.NRMSE_R_P,'omitnan');
Overall.NRMSE_L_P             = mean(T.NRMSE_L_P,'omitnan');

Overall.MeanLocRatio_T_pct    = 100*mean(T.FracLoc_T,'omitnan');
Overall.MeanLocRatio_M_pct    = 100*mean(T.FracLoc_M,'omitnan');
Overall.MeanLocRatio_P_pct    = 100*mean(T.FracLoc_P,'omitnan');

Overall.MeanTime_T_s          = mean(T.Time_T_s,'omitnan');
Overall.MeanTime_M_s          = mean(T.Time_M_s,'omitnan');
Overall.MeanTime_P_s          = mean(T.Time_P_s,'omitnan');

dTP = T.Error_T - T.Error_P;
dMP = T.Error_M - T.Error_P;
Overall.Diff_TminusP_mean     = mean(dTP,'omitnan');
Overall.Diff_MminusP_mean     = mean(dMP,'omitnan');

% --- NEW: overall anchors used into quick CSV overall ---
if ismember('AnchorsUsed_MOANS', T.Properties.VariableNames)
    Overall.MeanAnchorsUsed_M = mean(T.AnchorsUsed_MOANS,'omitnan');
end
if ismember('AnchorsUsed_Proposed', T.Properties.VariableNames)
    Overall.MeanAnchorsUsed_P = mean(T.AnchorsUsed_Proposed,'omitnan');
end

Overall.Topology              = topologyTag;
end



function pubStyle_LOCAL()
set(groot,'defaultAxesFontName','Times New Roman');
set(groot,'defaultTextFontName','Times New Roman');
set(groot,'defaultAxesFontSize',10);
set(groot,'defaultLineLineWidth',1.2);
set(groot,'defaultAxesLineWidth',1);
set(groot,'defaultAxesGridAlpha',.25);
set(groot,'defaultAxesBox','on');
set(groot,'defaultFigurePaperPositionMode','auto');
end


function plotMean_LOCAL(x,y,clr,linewidth)
good = isfinite(x)&isfinite(y);
[xs,ord] = sort(x(good)); ys = y(good);
ys = ys(ord);
plot(xs, ys, '-', 'Color', clr, 'LineWidth', linewidth);
end


function saveFig_LOCAL(fig, pathNoExt)
print(fig,[pathNoExt '.png'],'-dpng','-r300');
print(fig,[pathNoExt '.pdf'],'-dpdf');
end


function lbl = compactComboLabels_LOCAL(Tc)
lbl = cell(height(Tc),1);
for i=1:height(Tc)
    lbl{i} = sprintf('A=%g R=%g N=%d pct=%g', ...
        Tc.AreaSize(i), Tc.CommRange(i), Tc.TotalNodes(i), Tc.AnchorPct(i));
end
end


function plot_ecdf_LOCAL(v, clr, nameStr)
v=v(:); v=v(isfinite(v));
if isempty(v), return; end
try
    [f,x]=ecdf(v);
catch
    [f,x]=safe_ecdf_LOCAL(v);
end
plot(x,f,'-','Color',clr,'LineWidth',1.6,'DisplayName',nameStr);
end


function [f,x]=safe_ecdf_LOCAL(v)
v=sort(v(:));
[x,~,ic]=unique(v,'sorted');
f=cumsum(accumarray(ic,1))./numel(v);
end


function x = local_get(S, field, defaultVal)
if isstruct(S) && isfield(S,field)
    x = S.(field);
else
    x = defaultVal;
end
end


function s = slope1d_LOCAL(x,y)
x = x(:); y = y(:);
good = isfinite(x) & isfinite(y);
if nnz(good)<2
    s=NaN; 
    return;
end
x = x(good); y = y(good);
x = x - mean(x);
y = y - mean(y);
s = x\y;
end


function [dMean, ciLo, ciHi, pval] = pairedComboStats_LOCAL(T, G, colA, colB)
% Paired stats (Traditional - Proposed, etc.) per combo group
dMean = splitapply(@(a,b) mean(a-b,'omitnan'), T.(colA), T.(colB), G);
K = max(G);
ciLo = nan(K,1); ciHi = nan(K,1); pval = nan(K,1);
for k = 1:K
    a = T.(colA)(G==k); b = T.(colB)(G==k);
    good = isfinite(a) & isfinite(b);
    a=a(good); b=b(good);
    if numel(a) < 2, continue; end
    try
        [~, p, ci] = ttest(a,b);
        pval(k) = p; ciLo(k) = ci(1); ciHi(k) = ci(2);
    catch
        B=2000;
        dif = a-b;
        n=numel(dif);
        boots = zeros(B,1);
        for i=1:B
            idx = randi(n,n,1);
            boots(i) = mean(dif(idx));
        end
        ci = prctile(boots,[2.5 97.5]);
        ciLo(k)=ci(1); ciHi(k)=ci(2);
        pval(k) = 2*min(mean(boots<=0), mean(boots>=0));
    end
end
end


%% =========================================================================
%% ======================== CORE DV-HOP SUBROUTINES ========================
%% =========================================================================

function [hopCount, adjMatrix] = buildHopGraph(allPos, commRange, simParams)
% buildHopGraph
%   Build adjacency from distance <= commRange
%   Compute hopCount via graph shortest paths
%   Add noise, clip hops by maxHopCap, etc.
%   Force integer hops if simParams.useIntegerHops==true

    distMatrix = squareform(pdist(allPos));
    adjMatrix  = (distMatrix <= commRange);
    adjMatrix(1:size(adjMatrix,1)+1:end) = false;

    G = graph(adjMatrix);
    hopCount = distances(G);

    % link drop?
    if simParams.dropRate > 0
        mask = rand(size(hopCount)) < simParams.dropRate;
        hopCount(mask) = Inf;
    end

    % hop noise
    noiseStd = simParams.noiseStdRange(1) + diff(simParams.noiseStdRange) * rand();
    hopCount = hopCount + noiseStd * randn(size(hopCount));
    hopCount(hopCount < 0) = 0;

    % cap hops
    hopCount(hopCount > simParams.maxHopCap) = Inf;

    % integer hops?
    if isfield(simParams,'useIntegerHops') && simParams.useIntegerHops
        hopCount = round(hopCount);
        hopCount(hopCount < 0) = 0;
        hopCount(hopCount > simParams.maxHopCap) = Inf;
    end
end


function [meanError, estimatedPos] = runTraditionalDVHop(anchorPos, unknownPos, allPos, ...
    hopCount, adjMatrix, commRange, areaSize, simParams)
% runTraditionalDVHop
% - Traditional DV-Hop:
%   1. Compute avg hop distance per anchor using anchor-anchor hopcounts
%   2. Estimate distance to anchors for each unknown
%   3. Trilaterate

    %#ok<INUSD>
    numAnchors   = size(anchorPos, 1);
    numUnknowns  = size(unknownPos, 1);

    estimatedPos = NaN(numUnknowns, 2);

    % Anchor-anchor geodesic calibration
    anchorDist  = squareform(pdist(anchorPos));
    idxAnch     = 1:numAnchors;
    avgHopDists = nan(numAnchors,1);

    for i = 1:numAnchors
        hops  = hopCount(idxAnch(i), idxAnch);
        dists = anchorDist(i,:);
        valid = isfinite(hops) & hops >= 1 & hops <= simParams.maxHopCap & ...
                isfinite(dists) & dists>0;
        if any(valid)
            avgHopDists(i) = sum(dists(valid)) / sum(hops(valid));
        end
    end

    if any(isnan(avgHopDists))
        fillVal = median(avgHopDists(~isnan(avgHopDists)));
        if ~isfinite(fillVal)
            fillVal = commRange*0.8;
        end
        avgHopDists(isnan(avgHopDists)) = fillVal;
    end

    H = hopCount(1:numAnchors, numAnchors+1:end);
    estDists = bsxfun(@times, H, avgHopDists);

    for j = 1:numUnknowns
        idx = find(isfinite(estDists(:, j)) & estDists(:, j) > 0);
        if numel(idx) < 3
            continue;
        end
        anchors = anchorPos(idx,:);
        dists   = estDists(idx,j);

        pos = weighted_trilateration(anchors, dists);
        if any(isnan(pos))
            pos = trilaterationLeastSquares(anchors, dists);
        end
        if any(isnan(pos))
            continue;
        end
        estimatedPos(j,:) = min(max(pos, [0 0]), [areaSize areaSize]);
    end

    meanError = evaluateLocalization(unknownPos, estimatedPos, false);
end


%% =========================================================================
%% ========== Proposed Method (subset + enrichment + rescue/rollback) ======
%% =========================================================================
function [meanErrorProp, estProp, numAnchorsUsedFinal, finalIdx, errAll0, estAll0, covAllPct, timeAll0] = ...
    runProposed_Enriched(anchorPos, unknownPos, allPos, ...
                         hopCount, adjMatrix, ...
                         commRange, areaSize, ...
                         simParams, AA, ...
                         baselineErrorTrad, baselineErrorMOAN)
% (unchanged logic from your version; included in full for copy-paste)

    %#ok<INUSD>

    A               = size(anchorPos,1);
    allIdx          = (1:A).';
    numAnchorsTotal = A;

    dvprint('    [Proposed] total anchors available: %d\n', A);

    % --------- diagnostic: ALL anchors ------------------------------------------
    tAllDiag = tic;
    [estAll0] = estimateUnknownsWithAnchorsProposed( ...
        hopCount, anchorPos, allIdx, unknownPos, ...
        numAnchorsTotal, areaSize, commRange, allPos, simParams, 0);
    timeAll0 = toc(tAllDiag);

    errAll0   = evaluateLocalization(unknownPos, estAll0, false);
    covAllPct = estCoveragePct(estAll0);

    dvprint('    [Proposed] ALL-anchors diagnostic: Err=%.3f | Cov=%.1f%%\n', ...
        errAll0, covAllPct);

    % --------- STEP 1: initial subset via FiveStep -------------------------------
    [initAnchorPos, initIdx] = selectAnchors_FiveStep( ...
        anchorPos, hopCount, commRange, areaSize, ...
        numAnchorsTotal, AA);

    if numel(initIdx) < 3
        dvprint('    [Proposed] initial subset too small (<3). Fallback to ALL anchors.\n');
        initIdx       = allIdx;
        initAnchorPos = anchorPos(initIdx,:);
    end

    dvprint('    [Proposed] initial subset size: %d anchors\n', numel(initIdx));

    estInit = estimateUnknownsWithAnchorsProposed( ...
        hopCount, initAnchorPos, initIdx, unknownPos, ...
        numAnchorsTotal, areaSize, commRange, allPos, simParams, 0);

    currErr    = evaluateLocalization(unknownPos, estInit, false);
    currEst    = estInit;
    currIdx    = initIdx(:);
    currCovPct = estCoveragePct(estInit);

    bestErr    = currErr;
    bestEst    = currEst;
    bestIdx    = currIdx;

    dvprint('    [Proposed] init Err=%.3f | Cov=%.1f%% | beats Trad? %d | beats MOANS? %d\n', ...
        bestErr, currCovPct, (bestErr < baselineErrorTrad), (bestErr < baselineErrorMOAN));

    if (bestErr < baselineErrorTrad) && (bestErr < baselineErrorMOAN)
        dvprint('    [Proposed] init subset ALREADY beats both baselines. Skipping enrichment.\n');

        [bestErr, bestEst] = local_refineSubset(bestIdx, bestEst, bestErr, ...
            hopCount, unknownPos, numAnchorsTotal, areaSize, commRange, ...
            allPos, anchorPos, simParams);

        meanErrorProp       = bestErr;
        estProp             = bestEst;
        numAnchorsUsedFinal = numel(bestIdx);
        finalIdx            = bestIdx;
        return;
    end

    % =====================================================================
    % STEP 2: ENRICHMENT LOOP (add+re-prune)
    % =====================================================================

    remainingPool = setdiff(allIdx, currIdx, 'stable');
    keepGoing     = true;

    while keepGoing

        if isempty(remainingPool)
            dvprint('    [Enrich] no remaining anchors to test.\n');
            break;
        end

        dvprint('    [Enrich] trying %d candidate anchors...\n', numel(remainingPool));

        bestGainThisRound   = 0;
        bestCandThisRound   = NaN;
        bestIdxThisRound    = currIdx;
        bestEstThisRound    = currEst;
        bestErrThisRound    = bestErr;
        bestCovPctThisRound = currCovPct;

        for cand = reshape(remainingPool,1,[])

            [trialIdxPruned, okGeom] = try_merge_and_prune_viaFiveStep( ...
                currIdx, cand, anchorPos, hopCount, commRange, areaSize, AA);

            if ~okGeom
                dvprint('      cand %d: REJECT (<3 anchors survive FiveStep)\n', cand);
                continue;
            end

            trialEst = estimateUnknownsWithAnchorsProposed( ...
                hopCount, anchorPos(trialIdxPruned,:), trialIdxPruned, unknownPos, ...
                numAnchorsTotal, areaSize, commRange, allPos, simParams, 0);

            trialErr    = evaluateLocalization(unknownPos, trialEst, false);
            trialCovPct = estCoveragePct(trialEst);

            gain = bestErr - trialErr; % positive gain means improvement

            dvprint('      cand %d: trialIdxSize=%d  trialErr=%.3f gain=%.3f Cov=%.1f%% (geomOK)\n', ...
                cand, numel(trialIdxPruned), trialErr, gain, trialCovPct);

            improveLogic = (gain > 0) || ...
                (abs(gain) < 1e-12 && trialCovPct > bestCovPctThisRound + 1e-9);

            if improveLogic
                betterCandidate = false;

                if (gain > bestGainThisRound)
                    betterCandidate = true;
                elseif abs(gain - bestGainThisRound) < 1e-12 && ...
                       (trialCovPct > bestCovPctThisRound + 1e-9)
                    betterCandidate = true;
                end

                if betterCandidate
                    bestGainThisRound   = gain;
                    bestCandThisRound   = cand;
                    bestIdxThisRound    = trialIdxPruned(:);
                    bestEstThisRound    = trialEst;
                    bestErrThisRound    = trialErr;
                    bestCovPctThisRound = trialCovPct;
                end
            end
        end % for cand

        if ~isfinite(bestCandThisRound) || isnan(bestCandThisRound)
            dvprint('    [Enrich] no candidate improved error+coverage while passing geometry.\n');
            keepGoing = false;
            break;
        end

        dvprint('    [Enrich] ACCEPT via cand %d:\n', bestCandThisRound);
        dvprint('        Err %.3f -> %.3f (gain=%.3f), Cov %.1f%% -> %.1f%%, anchors %d -> %d\n', ...
            bestErr,    bestErrThisRound, bestGainThisRound, ...
            currCovPct, bestCovPctThisRound, ...
            numel(currIdx), numel(bestIdxThisRound));

        currIdx    = bestIdxThisRound;
        currEst    = bestEstThisRound;
        currErr    = bestErrThisRound;
        currCovPct = bestCovPctThisRound;

        bestIdx    = currIdx;
        bestEst    = currEst;
        bestErr    = currErr;

        remainingPool = setdiff(allIdx, currIdx, 'stable');

        if (bestErr < baselineErrorTrad) && (bestErr < baselineErrorMOAN)
            dvprint('    [Enrich] now BEATING both baselines! Err=%.3f < Trad %.3f & MOANS %.3f\n', ...
                bestErr, baselineErrorTrad, baselineErrorMOAN);
            keepGoing = false;
            break;
        end

        if isempty(remainingPool)
            dvprint('    [Enrich] pool empty, stopping.\n');
            keepGoing = false;
            break;
        end
    end % enrichment loop

    dvprint('    [Proposed] subset after enrichment: %d anchors, Err=%.3f, Cov=%.1f%%\n', ...
        numel(bestIdx), bestErr, currCovPct);

    % =====================================================================
    % STEP 3: PRUNE-TUNE LOOP (remove+re-prune)
    % =====================================================================

    keepPruning = true;
    while keepPruning
        if numel(bestIdx) <= 3
            dvprint('    [Prune] subset already tiny (<=3 anchors), stop prune-tune.\n');
            break;
        end

        dvprint('    [Prune] trying to remove each of %d anchors...\n', numel(bestIdx));

        pruneGainBest     = 0;
        pruneIdxBest      = bestIdx;
        pruneEstBest      = bestEst;
        pruneErrBest      = bestErr;
        pruneCovBest      = estCoveragePct(bestEst);
        prunedSomething   = false;
        removedAnchorBest = NaN;

        for ridx = 1:numel(bestIdx)
            anchorToRemove = bestIdx(ridx);

            [trialIdxAfterRemoval, okGeom2] = try_remove_and_prune_viaFiveStep( ...
                bestIdx, anchorToRemove, anchorPos, hopCount, commRange, areaSize, AA);

            if ~okGeom2
                dvprint('      drop %d: REJECT (<3 anchors survive FiveStep)\n', anchorToRemove);
                continue;
            end

            trialEst2 = estimateUnknownsWithAnchorsProposed( ...
                hopCount, anchorPos(trialIdxAfterRemoval,:), trialIdxAfterRemoval, unknownPos, ...
                numAnchorsTotal, areaSize, commRange, allPos, simParams, 0);

            trialErr2    = evaluateLocalization(unknownPos, trialEst2, false);
            trialCovPct2 = estCoveragePct(trialEst2);

            gain2 = bestErr - trialErr2; % positive means improvement

            dvprint('      drop %d: trialIdxSize=%d  trialErr=%.3f gain=%.3f Cov=%.1f%% (geomOK)\n', ...
                anchorToRemove, numel(trialIdxAfterRemoval), trialErr2, gain2, trialCovPct2);

            improveLogic2 = (gain2 > 0) || ...
                (abs(gain2) < 1e-12 && trialCovPct2 > pruneCovBest + 1e-9);

            if improveLogic2
                betterRemoval = false;

                if (gain2 > pruneGainBest)
                    betterRemoval = true;
                elseif abs(gain2 - pruneGainBest) < 1e-12 && ...
                       (trialCovPct2 > pruneCovBest + 1e-9)
                    betterRemoval = true;
                end

                if betterRemoval
                    pruneGainBest     = gain2;
                    pruneIdxBest      = trialIdxAfterRemoval(:);
                    pruneEstBest      = trialEst2;
                    pruneErrBest      = trialErr2;
                    pruneCovBest      = trialCovPct2;
                    prunedSomething   = true;
                    removedAnchorBest = anchorToRemove;
                end
            end
        end % for ridx

        if ~prunedSomething
            dvprint('    [Prune] no single-anchor removal improved error.\n');
            keepPruning = false;
            break;
        end

        dvprint('    [Prune] ACCEPT removal of anchor %d:\n', removedAnchorBest);
        dvprint('        Err %.3f -> %.3f (gain=%.3f), Cov %.1f%% -> %.1f%%, anchors %d -> %d\n', ...
            bestErr, pruneErrBest, pruneGainBest, ...
            pruneCovBest, pruneCovBest, ...
            numel(bestIdx), numel(pruneIdxBest));

        bestIdx = pruneIdxBest;
        bestEst = pruneEstBest;
        bestErr = pruneErrBest;

        if (bestErr < baselineErrorTrad) && (bestErr < baselineErrorMOAN)
            dvprint('    [Prune] now BEATING both baselines after removal! Err=%.3f < Trad %.3f & MOANS %.3f\n', ...
                bestErr, baselineErrorTrad, baselineErrorMOAN);
            keepPruning = false;
            break;
        end
    end % prune-tune loop

    dvprint('    [Proposed] subset after prune-tune: %d anchors, Err=%.3f\n', ...
        numel(bestIdx), bestErr);

    % =====================================================================
    % STEP 4: FALLBACK to ALL anchors if still strictly better
    % =====================================================================
    if errAll0 + 1e-12 < bestErr
        dvprint('    [Fallback] ALL anchors beats tuned subset (%.3f < %.3f). Using ALL.\n', ...
            errAll0, bestErr);
        bestErr = errAll0;
        bestEst = estAll0;
        bestIdx = allIdx;
    end

    % =====================================================================
    % STEP 5: FINAL REFINE (rp = 1..2)
    % =====================================================================
    [bestErr, bestEst] = local_refineSubset(bestIdx, bestEst, bestErr, ...
        hopCount, unknownPos, numAnchorsTotal, areaSize, commRange, ...
        allPos, anchorPos, simParams);

    dvprint('    [Refine] final Err=%.3f after polish\n', bestErr);

    % --------- OUTPUTS ----------------------------------------------------------
    meanErrorProp       = bestErr;
    estProp             = bestEst;
    numAnchorsUsedFinal = numel(bestIdx);
    finalIdx            = bestIdx;
end


function [trialIdxPrunedGlobal, okGeom] = try_merge_and_prune_viaFiveStep( ...
        currIdx, cand, anchorPos, hopCount, commRange, areaSize, AA)

    trialIdxGlobal = unique([currIdx; cand], 'stable');
    trialPos       = anchorPos(trialIdxGlobal,:);
    hopSub         = hopCount(trialIdxGlobal, trialIdxGlobal);
    numAnchorsTrial= numel(trialIdxGlobal);

    [~, prunedLocalIdx] = selectAnchors_FiveStep( ...
        trialPos, hopSub, commRange, areaSize, ...
        numAnchorsTrial, AA);

    trialIdxPrunedGlobal = trialIdxGlobal(prunedLocalIdx);
    okGeom = numel(trialIdxPrunedGlobal) >= 3;
end


function [trialIdxPrunedGlobal, okGeom2] = try_remove_and_prune_viaFiveStep( ...
        bestIdx, badAnchor, anchorPos, hopCount, commRange, areaSize, AA)

    reducedIdxGlobal = bestIdx(bestIdx~=badAnchor);
    reducedPos       = anchorPos(reducedIdxGlobal,:);

    if numel(reducedIdxGlobal) < 3
        trialIdxPrunedGlobal = reducedIdxGlobal;
        okGeom2 = false;
        return;
    end

    hopSub2          = hopCount(reducedIdxGlobal, reducedIdxGlobal);
    numAnchorsRed    = numel(reducedIdxGlobal);

    [~, prunedLocalIdx2] = selectAnchors_FiveStep( ...
        reducedPos, hopSub2, commRange, areaSize, ...
        numAnchorsRed, AA);

    trialIdxPrunedGlobal = reducedIdxGlobal(prunedLocalIdx2);
    okGeom2 = numel(trialIdxPrunedGlobal) >= 3;
end


function [outErr, outEst] = local_refineSubset(anchorIdx, currEst, currErr, ...
        hopCount, unknownPos, numAnchorsTotal, areaSize, commRange, ...
        allPos, anchorPos, simParams)

    bestErr = currErr;
    bestEst = currEst;

    for rp = 1:2
        estTry = estimateUnknownsWithAnchorsProposed( ...
            hopCount, ...
            anchorPos(anchorIdx,:), ...
            anchorIdx, ...
            unknownPos, ...
            numAnchorsTotal, ...
            areaSize, ...
            commRange, ...
            allPos, ...
            simParams, ...
            rp);

        errTry = evaluateLocalization(unknownPos, estTry, false);

        dvprint('    [Refine] rp=%d -> Err=%.3f (best so far %.3f)\n', rp, errTry, bestErr);

        if errTry < bestErr
            bestErr = errTry;
            bestEst = estTry;
        else
            break; % stop if no more gain
        end
    end

    outErr = bestErr;
    outEst = bestEst;
end


function [estPos, avgHopDists, anchorsUsedCounts] = estimateUnknownsWithAnchorsProposed( ...
    hopCount, selectedAnchorPos, finalIdx, unknownPos, originalNumAnchors, ...
    areaSize, commRange, allPos, simParams, refinePassIdx)
% (unchanged; full body preserved) — bias-corrected per-node ring filter etc.

    %#ok<INUSD>

    Ktot = numel(finalIdx);
    U    = size(unknownPos,1);

    estPos            = NaN(U,2);
    anchorsUsedCounts = zeros(U,1);
    avgHopDists       = nan(Ktot,1);

    maxHopThreshold = simParams.maxHopCap;

    anchorDist = squareform(pdist(selectedAnchorPos));  % K x K

    for i = 1:Ktot
        hops_ij  = hopCount(finalIdx(i), finalIdx);  % 1 x K
        dists_ij = anchorDist(i,:);                 % 1 x K
        valid = isfinite(hops_ij) & ...
                (hops_ij >= 1) & (hops_ij <= maxHopThreshold) & ...
                isfinite(dists_ij) & (dists_ij > 0);
        if any(valid)
            avgHopDists(i) = sum(dists_ij(valid)) / sum(hops_ij(valid));
        end
    end

    if any(isnan(avgHopDists))
        fallbackVal = median(avgHopDists(~isnan(avgHopDists)));
        if ~isfinite(fallbackVal)
            fallbackVal = 0.8 * commRange;
        end
        avgHopDists(isnan(avgHopDists)) = fallbackVal;
    end

    H = hopCount(finalIdx, originalNumAnchors+1:end);  % K x U
    distEstMat = bsxfun(@times, H, avgHopDists);       % K x U
    distEstMat(~isfinite(distEstMat) | distEstMat <= 0) = NaN;

    MIN_SOLVE_ANCH = 3;

    if Ktot <= 12
        MIN_AFTER_PRUNE = max(6, MIN_SOLVE_ANCH);
        MAD_MULT        = 3.0;
        MAX_PRUNE_ITERS = 3;
        KMAX_NEAR_GLOBAL= Ktot;
    else
        MIN_AFTER_PRUNE    = 4;
        MAD_MULT           = 2.5;
        MAX_PRUNE_ITERS    = 6;
        KMAX_FRAC_SELECTED = 0.95;
        KMAX_NEAR_GLOBAL   = max(MIN_SOLVE_ANCH, floor(KMAX_FRAC_SELECTED * Ktot));
    end

    RING_FRAC        = 0.45;
    BASE_AREA_FACTOR = 0.0015;
    MAX_KEPT_GEOM    = 12;

    for uIdx = 1:U
        rAll    = distEstMat(:,uIdx);
        goodSet = find(isfinite(rAll) & rAll > 0);
        if numel(goodSet) < MIN_SOLVE_ANCH
            continue;
        end

        [~, ordNear] = sort(rAll(goodSet),'ascend');
        idxCand = goodSet(ordNear);
        if numel(idxCand) > KMAX_NEAR_GLOBAL
            idxCand = idxCand(1:KMAX_NEAR_GLOBAL);
        end

        rCandAll = rAll(idxCand);
        Araw     = selectedAnchorPos(idxCand,:);

        medR     = median(rCandAll);
        band     = RING_FRAC * medR;
        ringMask = abs(rCandAll - medR) <= band;
        tooSkewed = (medR > 1.5 * min(rCandAll));

        if (~tooSkewed) && (nnz(ringMask) >= MIN_SOLVE_ANCH)
            idxCand  = idxCand(ringMask);
            rCandAll = rAll(idxCand);
            Araw     = selectedAnchorPos(idxCand,:);
        end

        baseMinArea  = BASE_AREA_FACTOR * (commRange^2);
        keepGeoLocal = enforceMinArea(Araw, baseMinArea, ...
                           min([MAX_KEPT_GEOM, numel(idxCand), KMAX_NEAR_GLOBAL]));

        idxCand = idxCand(keepGeoLocal);
        rCand   = rAll(idxCand);
        Apos    = selectedAnchorPos(idxCand,:);

        if numel(idxCand) < MIN_SOLVE_ANCH
            continue;
        end

        fullIdx_forFallback = goodSet;
        rAll_full           = rAll(fullIdx_forFallback);
        Aall_full           = selectedAnchorPos(fullIdx_forFallback,:);

        pos_u = weighted_trilateration(Apos, rCand);
        if any(isnan(pos_u))
            pos_u = trilaterationLeastSquares(Apos, rCand);
        end
        if any(isnan(pos_u))
            continue;
        end

        geomDist = vecnorm(Apos - pos_u, 2, 2);
        alpha    = computeAlpha(rCand, geomDist);
        rCal     = alpha * rCand;

        pos_u = weighted_trilateration(Apos, rCal);
        if any(isnan(pos_u))
            pos_u = trilaterationLeastSquares(Apos, rCal);
        end
        if any(isnan(pos_u))
            continue;
        end

        for it = 1:MAX_PRUNE_ITERS
            geomDist_now = vecnorm(Apos - pos_u, 2, 2);
            alpha_now    = computeAlpha(rCand, geomDist_now);
            rCal_now     = alpha_now * rCand;

            geomNow = vecnorm(Apos - pos_u, 2, 2);
            res     = abs(geomNow - rCal_now);

            medRes  = median(res);
            MADv    = mad(res,1);
            thr     = medRes + MAD_MULT * MADv;

            if numel(rCand) <= MIN_AFTER_PRUNE
                pos_tmp = weighted_trilateration(Apos, rCal_now);
                if any(isnan(pos_tmp))
                    pos_tmp = trilaterationLeastSquares(Apos, rCal_now);
                end
                if all(isfinite(pos_tmp))
                    pos_u = pos_tmp;
                end
                break;
            end

            badSet = find(res > thr);
            if isempty(badSet)
                pos_tmp = weighted_trilateration(Apos, rCal_now);
                if any(isnan(pos_tmp))
                    pos_tmp = trilaterationLeastSquares(Apos, rCal_now);
                end
                if all(isfinite(pos_tmp))
                    pos_u = pos_tmp;
                end
                break;
            end

            [~, worstLocal] = max(res);
            survivors = setdiff(1:numel(rCand), worstLocal);
            if numel(survivors) < MIN_SOLVE_ANCH
                break;
            end

            Apos  = Apos(survivors,:);
            rCand = rCand(survivors);

            pos_u = weighted_trilateration(Apos, rCand);
            if any(isnan(pos_u))
                pos_u = trilaterationLeastSquares(Apos, rCand);
            end
            if any(isnan(pos_u))
                break;
            end
        end

        if any(isnan(pos_u))
            continue;
        end

        [Apos_bal, rCand_bal] = selectSectorBalancedSubset( ...
                                    pos_u, Aall_full, rAll_full, Apos, rCand);

        pos_bal = weighted_trilateration(Apos_bal, rCand_bal);
        if any(isnan(pos_bal))
            pos_bal = trilaterationLeastSquares(Apos_bal, rCand_bal);
        end

        if all(isfinite(pos_bal))
            geom_curr   = vecnorm(Apos     - pos_u,   2, 2);
            alpha_curr  = computeAlpha(rCand,     geom_curr);
            rCurr_cal   = alpha_curr * rCand;
            fitRes_curr = mean(abs(geom_curr - rCurr_cal), 'omitnan');

            geom_bal   = vecnorm(Apos_bal - pos_bal, 2, 2);
            alpha_bal  = computeAlpha(rCand_bal, geom_bal);
            rBal_cal   = alpha_bal * rCand_bal;
            fitRes_bal = mean(abs(geom_bal - rBal_cal), 'omitnan');

            if fitRes_bal < fitRes_curr
                pos_u = pos_bal;
                Apos  = Apos_bal;
                rCand = rCand_bal;
            end
        end

        geomDist_test = vecnorm(Apos - pos_u, 2, 2);
        alpha_final   = computeAlpha(rCand, geomDist_test);
        rCal_final    = alpha_final * rCand;
        fitRes        = mean(abs(geomDist_test - rCal_final), 'omitnan');

        if fitRes > 0.5 * commRange
            rFB  = rAll_full;
            A_FB = Aall_full;

            pos_tmp = weighted_trilateration(A_FB, rFB);
            if any(isnan(pos_tmp))
                pos_tmp = trilaterationLeastSquares(A_FB, rFB);
            end
            if all(isfinite(pos_tmp))
                geomFB   = vecnorm(A_FB - pos_tmp,2,2);
                alphaFB  = computeAlpha(rFB, geomFB);
                rFBcal   = alphaFB * rFB;

                pos_tmp2 = weighted_trilateration(A_FB, rFBcal);
                if any(isnan(pos_tmp2))
                    pos_tmp2 = trilaterationLeastSquares(A_FB, rFBcal);
                end

                if all(isfinite(pos_tmp2))
                    pos_u = pos_tmp2;
                    Apos  = A_FB;
                else
                    pos_u = pos_tmp;
                    Apos  = A_FB;
                end
            end
        end

        pos_u = min(max(pos_u, [0 0]), [areaSize areaSize]);

        estPos(uIdx,:)            = pos_u;
        anchorsUsedCounts(uIdx,1) = size(Apos,1);
    end
end

function alpha = computeAlpha(rVec, geomDistVec)
    denom = sum(rVec.^2);
    if denom <= eps
        alpha = 1.0;
        return;
    end
    alpha = sum(rVec .* geomDistVec) / denom;
    if ~isfinite(alpha) || (alpha <= 0)
        alpha = 1.0;
    end
end

function [Akeep, rkeep] = selectSectorBalancedSubset(pos_u, Aall_full, rAll_full, Acore, rcore)
    if size(Aall_full,1) < 3
        Akeep = Acore; rkeep = rcore; return;
    end
    rel = Aall_full - pos_u;
    ang = atan2(rel(:,2), rel(:,1));
    NUM_SECTORS = 8;
    sectorSize  = 2*pi / NUM_SECTORS;
    sectorIdx   = floor( (ang + pi) / sectorSize ) + 1;
    inCoreMaskGlobal = ismember(Aall_full, Acore, 'rows');

    finiteRanges = rAll_full(isfinite(rAll_full) & rAll_full>0);
    if isempty(finiteRanges)
        baseMed = 1.0;
    else
        baseMed = median(finiteRanges);
        if ~isfinite(baseMed) || baseMed <= 0
            baseMed = 1.0;
        end
    end
    lambda = 0.2 * baseMed;

    keepMask = false(size(Aall_full,1),1);
    for s = 1:NUM_SECTORS
        inSector = find(sectorIdx == s);
        if isempty(inSector), continue; end
        inCoreLocal = inCoreMaskGlobal(inSector);
        sectRanges  = rAll_full(inSector);
        sectRanges(~isfinite(sectRanges) | sectRanges<=0) = inf;
        score = sectRanges + lambda * (~inCoreLocal);
        [~,ord] = sort(score,'ascend');
        pick = inSector(ord(1:min(2,numel(ord))));
        keepMask(pick) = true;
    end

    Akeep = Aall_full(keepMask,:);
    rkeep = rAll_full(keepMask);
    if numel(rkeep) < 3
        Akeep = Acore; rkeep = rcore;
    end
end

function keepIdx = enforceMinArea(anchorSetPos, minAreaThresh, maxKeep)
    K = size(anchorSetPos,1);
    if K <= 3
        keepIdx = (1:K).';
        return;
    end
    triArea = @(A,B,C) 0.5 * abs(det([B-A; C-A]));
    ctr  = mean(anchorSetPos,1);
    d2c  = vecnorm(anchorSetPos - ctr, 2, 2);
    [~,seedIdx] = min(d2c);
    chosen = seedIdx; pool = setdiff(1:K, seedIdx);
    while true
        if numel(chosen) >= maxKeep, break; end
        if isempty(pool), break; end
        bestScore = -Inf; bestCand  = [];
        currPos  = anchorSetPos(chosen,:);
        currCent = mean(currPos,1);
        for cand = pool(:).'
            cPos = anchorSetPos(cand,:);
            spreadScore = norm(cPos - currCent);
            tmpIdx = [chosen(:); cand];
            tmpPos = anchorSetPos(tmpIdx,:);
            goodTri     = false;
            maxAreaSeen = 0;
            if size(tmpPos,1) >= 3
                combs = nchoosek(1:size(tmpPos,1),3);
                for ii = 1:size(combs,1)
                    A = tmpPos(combs(ii,1),:);
                    B = tmpPos(combs(ii,2),:);
                    C = tmpPos(combs(ii,3),:);
                    a = triArea(A,B,C);
                    maxAreaSeen = max(maxAreaSeen, a);
                    if a >= minAreaThresh
                        goodTri = true;
                    end
                end
            end
            geomBoost = 2.0 * double(goodTri);
            score = geomBoost + 1.0*maxAreaSeen + 0.5*spreadScore;
            if score > bestScore, bestScore = score; bestCand  = cand; end
        end
        if isempty(bestCand), break; end
        chosen(end+1) = bestCand; %#ok<AGROW>
        pool(pool==bestCand) = [];
    end
    finalPos = anchorSetPos(chosen,:);
    okGeom   = false;
    if size(finalPos,1) >= 3
        combs = nchoosek(1:size(finalPos,1),3);
        for ii = 1:size(combs,1)
            A = finalPos(combs(ii,1),:);
            B = finalPos(combs(ii,2),:);
            C = finalPos(combs(ii,3),:);
            if triArea(A,B,C) >= minAreaThresh
                okGeom = true; break;
            end
        end
    end
    if ~okGeom
        if K >= 3
            combsK = nchoosek(1:K,3);
            bestArea = -Inf; bestTrip = combsK(1,:);
            for ii = 1:size(combsK,1)
                A = anchorSetPos(combsK(ii,1),:);
                B = anchorSetPos(combsK(ii,2),:);
                C = anchorSetPos(combsK(ii,3),:);
                a = triArea(A,B,C);
                if a > bestArea, bestArea = a; bestTrip = combsK(ii,:); end
            end
            chosen = bestTrip(:).';
        else
            chosen = 1:K;
        end
    end
    keepIdx = chosen(:);
end

function good = isGoodAnchorSet(currErr, currCovPct, errAll, covAll)
    ERR_SLACK      = 1.15;
    COV_FLOOR_REL  = 0.90;
    if ~isfinite(currErr) || ~isfinite(errAll), good = false; return; end
    if currErr > ERR_SLACK * errAll, good = false; return; end
    if currCovPct < COV_FLOOR_REL * covAll, good = false; return; end
    good = true;
end

function nextAnchor = chooseAnchorToAdd(pool, currIdx, anchorPos, commRange)
    currSetPos = anchorPos(currIdx,:);
    centroid   = mean(currSetPos,1);
    bestScore = -Inf; bestID    = pool(1);
    for cand = reshape(pool,1,[])
        candPos = anchorPos(cand,:);
        distCent = norm(candPos - centroid);
        distToSet = min(vecnorm(currSetPos - candPos,2,2));
        score = 0.6*distCent + 0.4*(distToSet / max(commRange,1));
        if score > bestScore, bestScore = score; bestID    = cand; end
    end
    nextAnchor = bestID;
end


%% =========================================================================
%% ========== Anchor subset selection used by Proposed algorithm ===========
%% =========================================================================
function [selectedAnchorPos, finalIdx] = selectAnchors_FiveStep( ...
            anchorPos, hopCount, commRange, areaSize, originalNumAnchors, AA)
% (unchanged; full logic preserved)

    A = originalNumAnchors;
    if A < 3
        finalIdx = (1:A).';
        selectedAnchorPos = anchorPos;
        return;
    end

    params = local_adaptThresholdsLite(anchorPos, hopCount, commRange, A, AA.filteringMode);

    baseMinArea = params.minAreaTri;
    keep1 = removeCollinearBasic(anchorPos, baseMinArea);

    idx_afterGeom1 = keep1(:);
    pos_afterGeom1 = anchorPos(idx_afterGeom1,:);

    if numel(idx_afterGeom1) < 3
        finalIdx = (1:A).';
        selectedAnchorPos = anchorPos;
        return;
    end

    anchorsIdxGlobal = idx_afterGeom1(:);
    posGeom          = pos_afterGeom1;

    Haa = hopCount(anchorsIdxGlobal, anchorsIdxGlobal);
    twoHopAdj = (Haa <= 2);
    oneHopDeg = sum(Haa <= 1, 2); %#ok<NASGU>
    twoHopDeg = sum(twoHopAdj, 2);

    domMask = buildTwoHopDomSetDeg(twoHopAdj, twoHopDeg);

    idx_afterDom = anchorsIdxGlobal(domMask);
    pos_afterDom = anchorPos(idx_afterDom,:);

    if numel(idx_afterDom) < 3
        idx_afterDom = anchorsIdxGlobal;
        pos_afterDom = posGeom;
    end

    idx_afterCov = pruneByUnique2HopCoverage(idx_afterDom, hopCount, A, params.minUniqueUnknowns);

    if numel(idx_afterCov) < 3
        idx_afterCov = idx_afterDom;
    end
    pos_afterCov = anchorPos(idx_afterCov,:);

    minKeep = max(3, ceil(AA.minAnchorsFrac * A));
    if numel(idx_afterCov) < minKeep && numel(idx_afterDom) >= minKeep
        idx_afterCov = idx_afterDom;
        pos_afterCov = pos_afterDom;
    end

    maxKeep = max(minKeep, min(numel(idx_afterCov), params.maxKeep));
    keepGeom2 = enforceTriangleAreaMin(pos_afterCov, baseMinArea, maxKeep);

    finalIdx = idx_afterCov(keepGeom2);
    selectedAnchorPos = anchorPos(finalIdx,:);

    if numel(finalIdx) < 3
        finalIdx = idx_afterCov;
        selectedAnchorPos = anchorPos(finalIdx,:);
    end
end

function keepLocalIdx = enforceTriangleAreaMin(anchorSetPos, minAreaThresh, maxKeep)
    K = size(anchorSetPos,1);
    if K <= 3, keepLocalIdx = (1:K).'; return; end
    triArea = @(A,B,C) 0.5 * abs(det([B-A; C-A]));
    ctr = mean(anchorSetPos,1);
    d2c = vecnorm(anchorSetPos - ctr, 2, 2);
    [~, seedIdx] = min(d2c);
    chosen = seedIdx;
    pool   = setdiff(1:K, seedIdx);
    while numel(chosen) < maxKeep && ~isempty(pool)
        bestCand  = [];
        bestScore = -Inf;
        currPos  = anchorSetPos(chosen,:);
        currCent = mean(currPos,1);
        for cand = pool(:).'
            cPos = anchorSetPos(cand,:);
            spreadScore = norm(cPos - currCent);
            tmpIdx = [chosen(:); cand];
            tmpPos = anchorSetPos(tmpIdx,:);
            maxAreaSeen = 0;
            if size(tmpPos,1) >= 3
                combs = nchoosek(1:size(tmpPos,1),3);
                for ii = 1:size(combs,1)
                    A = tmpPos(combs(ii,1),:);
                    B = tmpPos(combs(ii,2),:);
                    C = tmpPos(combs(ii,3),:);
                    a = triArea(A,B,C);
                    if a > maxAreaSeen, maxAreaSeen = a; end
                end
            end
            score = 1.0*spreadScore + 2.0*maxAreaSeen;
            if score > bestScore, bestScore = score; bestCand  = cand; end
        end
        if isempty(bestCand), break; end
        chosen(end+1) = bestCand; %#ok<AGROW>
        pool(pool==bestCand) = [];
    end
    finalPos = anchorSetPos(chosen,:);
    goodTri = false;
    if size(finalPos,1) >= 3
        combs = nchoosek(1:size(finalPos,1),3);
        for ii = 1:size(combs,1)
            A = finalPos(combs(ii,1),:);
            B = finalPos(combs(ii,2),:);
            C = finalPos(combs(ii,3),:);
            a = triArea(A,B,C);
            if a >= minAreaThresh, goodTri = true; break; end
        end
    end
    if ~goodTri && K >= 3
        combsK = nchoosek(1:K,3); bestPer = -Inf; bestTrip = combsK(1,:);
        for ii = 1:size(combsK,1)
            A = anchorSetPos(combsK(ii,1),:);
            B = anchorSetPos(combsK(ii,2),:);
            C = anchorSetPos(combsK(ii,3),:);
            per = norm(A-B)+norm(B-C)+norm(C-A);
            if per > bestPer, bestPer=per; bestTrip = combsK(ii,:); end
        end
        chosen = bestTrip(:).';
    end
    keepLocalIdx = chosen(:);
end

function domMask = buildTwoHopDomSetDeg(twoHopAdj, twoHopDeg)
    K = size(twoHopAdj,1);
    picked = false(K,1);
    [~, order] = sort(twoHopDeg, 'descend');
    dominatesAll = @(mask) all(any(twoHopAdj(mask,:),1));
    for idx = 1:K
        if dominatesAll(picked), break; end
        cand = order(idx);
        picked(cand) = true;
    end
    if ~any(picked), picked(order(1)) = true; end
    domMask = picked;
end

function keptIdx = pruneByUnique2HopCoverage(currAnchorIdx, hopCount, A, minUniqueUnknowns)
    Ustart = size(hopCount,2) - A;
    if Ustart <= 0, keptIdx = currAnchorIdx(:); return; end
    unknownGlobalIdx = (A+1):(A+Ustart);
    S = currAnchorIdx(:);
    K = numel(S);
    if K <= 3, keptIdx = S; return; end
    coverMat = false(K, Ustart);
    for ii = 1:K
        aID = S(ii);
        hops_to_unks = hopCount(aID, unknownGlobalIdx);
        coverMat(ii,:) = (hops_to_unks <= 2);
    end
    keepMask = true(K,1);
    for ii = 1:K
        if ~keepMask(ii), continue; end
        thisCov = coverMat(ii,:);
        if ~any(thisCov)
            keepMask(ii) = false; continue;
        end
        others = setdiff(1:K, ii);
        otherCov = any( coverMat(others,:), 1 );
        uniqUnknowns = thisCov & ~otherCov;
        nUnique = nnz(uniqUnknowns);
        if nUnique < minUniqueUnknowns
            keepMask(ii) = false;
        end
    end
    if nnz(keepMask) < 3, keepMask(:) = true; end
    keptIdx = S(keepMask);
end

function params = local_adaptThresholdsLite(anchorPos, hopCount, commRange, numAnchors, mode)
    if nargin < 5, mode = 'moderate'; end
    baseArea = (commRange^2);
    switch lower(mode)
        case 'soft'
            areaFactor = 0.0015; uniqFrac = 0.02; maxFrac = 0.80;
        case 'hard'
            areaFactor = 0.0030; uniqFrac = 0.08; maxFrac = 0.60;
        otherwise
            areaFactor = 0.0020; uniqFrac = 0.05; maxFrac = 0.70;
    end
    params.minAreaTri = areaFactor * baseArea;
    totalNodes   = size(hopCount,2);
    totalUnknown = totalNodes - numAnchors;
    params.minUniqueUnknowns = max(1, round(uniqFrac * totalUnknown));
    params.maxKeep = max(3, ceil(maxFrac * numAnchors));
end

function params = adaptThresholds(anchorPos, hopCount, commRange, numAnchors, mode)
% (kept for completeness; not used directly by main pipeline)
    if nargin < 5, mode = 'moderate'; end
    if size(anchorPos,1) < 2
        distVec = commRange/2;
        avgDist = commRange/2; %#ok<NASGU>
    else
        distVec = pdist(anchorPos);
        avgDist = exp(mean(log(max(distVec, eps)))); %#ok<NASGU>
    end
    baseArea = mean(distVec)^2; %#ok<NASGU>
    switch lower(mode)
        case 'soft'
            params.minArea   = 0.0035 * baseArea;
            params.minUnique = max(1, round(0.035 * (size(hopCount,2)-numAnchors)));
            params.minRatio  = 0.66;
        case 'hard'
            params.minArea   = 0.0130 * baseArea;
            params.minUnique = max(1, round(0.100 * (size(hopCount,2)-numAnchors)));
            params.minRatio  = 0.76;
        otherwise
            params.minArea   = 0.0085 * baseArea;
            params.minUnique = max(1, round(0.070 * (size(hopCount,2)-numAnchors)));
            params.minRatio  = 0.70;
    end
end

function keepIdx = removeCollinearBasic(anchorPos, minAreaThresh)
    N = size(anchorPos,1);
    if N <= 3
        keepIdx = (1:N).';
        return;
    end
    triArea = @(A,B,C) 0.5*abs(det([B-A; C-A]));
    keepMask = true(N,1);
    combs = nchoosek(1:N,3);
    for ii = 1:size(combs,1)
        t = combs(ii,:);
        if ~all(keepMask(t)), continue; end
        A = anchorPos(t(1),:);
        B = anchorPos(t(2),:);
        C = anchorPos(t(3),:);
        areaABC = triArea(A,B,C);
        if areaABC < minAreaThresh
            dA = norm(B-A)+norm(C-A);
            dB = norm(A-B)+norm(C-B);
            dC = norm(A-C)+norm(B-C);
            [~,worstLocal] = min([dA dB dC]);
            killIdx = t(worstLocal);
            keepMask(killIdx) = false;
        end
    end
    if nnz(keepMask) < 3
        keepMask(:) = true;
    end
    keepIdx = find(keepMask);
end

function [sel, filt] = pruneRedundantAnchors(idxs, hop, minUnique, originalN)
    unks = (originalN+1):size(hop,2);
    cov  = hop(idxs, unks) <= 3;
    keep = true(numel(idxs),1);
    for i = 1:numel(idxs)
        others = any(cov(setdiff(1:numel(idxs), i),:), 1);
        uniqueCov = sum(cov(i,:) & ~others);
        if uniqueCov < minUnique
            keep(i) = false;
        end
    end
    sel = find(keep);
    if numel(sel) < numel(idxs)*0.5
        sel = (1:numel(idxs)).';
    end
    filt = hop(idxs(sel), :);
end

function sel = nodeDegreeBasedIMCDS(anchorPos, commRange, minRatio)
    N = size(anchorPos,1);
    if N==0, sel=[]; return; end
    D = squareform(pdist(anchorPos));
    A1 = (D <= commRange);
    A1(1:N+1:end) = false;
    A2 = A1 | (A1*A1>0);
    A2(1:N+1:end) = true;
    deg1 = sum(A1,2);
    [~, order] = sort(deg1,'descend');
    picked = false(N,1);
    picked(order(1)) = true;
    minKeep = ceil(minRatio * N);
    if minKeep < 1, minKeep = 1; end
    while ~isConnectedDominatingSet2Hop(A2, picked)
        cand = find(~picked);
        if isempty(cand), break; end
        [~,bestLocal] = max(deg1(cand));
        picked(cand(bestLocal)) = true;
        if sum(picked) >= minKeep, break; end
    end
    while sum(picked) < minKeep
        cand = find(~picked);
        if isempty(cand), break; end
        [~,bestLocal] = max(deg1(cand));
        picked(cand(bestLocal)) = true;
    end
    sel = find(picked);
end

function ok = isConnectedDominatingSet2Hop(A2, pickedMask)
    if ~any(pickedMask)
        ok = false; return;
    end
    pickedIdx = find(pickedMask);
    subA2 = A2(pickedIdx, pickedIdx);
    okConn = all(all(subA2));
    if ~okConn, ok = false; return; end
    reachFromPicked = any(A2(:, pickedIdx), 2);
    okDom = all(reachFromPicked);
    ok = okConn && okDom;
end


%% =========================================================================
%% ========== Hop-distance correction + unknown localization (LS) ==========
%% =========================================================================
function [estPos, avgHopDists, anchorsUsedCounts] = estimateUnknownsWithAnchors( ...
    hopCount, selectedAnchorPos, finalIdx, unknownPos, originalNumAnchors, ...
    areaSize, commRange, allPos, simParams, refinePassIdx)
% (kept for compatibility; not called by main Proposed path)
    %#ok<INUSD>
    Ktot = numel(finalIdx);
    U    = size(unknownPos,1);
    estPos            = NaN(U,2);
    anchorsUsedCounts = zeros(U,1);
    avgHopDists       = nan(Ktot,1);
    maxHopThreshold   = simParams.maxHopCap;

    anchorDist = squareform(pdist(selectedAnchorPos));
    for i = 1:Ktot
        hops_ij  = hopCount(finalIdx(i), finalIdx);
        dists_ij = anchorDist(i,:);
        valid = isfinite(hops_ij) & ...
                (hops_ij >= 1) & ...
                (hops_ij <= maxHopThreshold) & ...
                isfinite(dists_ij) & (dists_ij > 0);
        if any(valid)
            avgHopDists(i) = sum(dists_ij(valid)) / sum(hops_ij(valid));
        end
    end
    if any(isnan(avgHopDists))
        fillVal = median(avgHopDists(~isnan(avgHopDists)));
        if ~isfinite(fillVal), fillVal = 0.8 * commRange; end
        avgHopDists(isnan(avgHopDists)) = fillVal;
    end

    H = hopCount(finalIdx, originalNumAnchors+1:end);
    distEstMat = bsxfun(@times, H, avgHopDists);
    distEstMat(~isfinite(distEstMat) | distEstMat<=0) = NaN;

    KMAX_NEAR          = 18;
    FAR_MULT           = 2.0;
    BASE_AREA_FACTOR   = 0.0015;
    MAX_KEEP_AFTER_GEO = 14;
    MIN_ANCHORS_SOLVE  = 3;
    MIN_ANCHORS_AFTER  = 4;
    MAX_PRUNE_ITERS    = 6;
    MAD_THRESH_MULT    = 2.5;

    for uIdx = 1:U
        d_u = distEstMat(:,uIdx);
        idxReach = find(isfinite(d_u) & d_u>0);
        if numel(idxReach) < MIN_ANCHORS_SOLVE
            continue;
        end
        [~, ordLocal] = sort(d_u(idxReach),'ascend');
        idxCand = idxReach(ordLocal);
        if numel(idxCand) > KMAX_NEAR
            idxCand = idxCand(1:KMAX_NEAR);
        end
        rCand = d_u(idxCand);
        Aall  = selectedAnchorPos;
        AposAll_u = Aall(idxCand,:);
        medR   = median(rCand);
        farCut = FAR_MULT * medR;
        keepNearMask = (rCand <= farCut);
        if nnz(keepNearMask) >= MIN_ANCHORS_SOLVE
            idxCand    = idxCand(keepNearMask);
            rCand      = d_u(idxCand);
            AposAll_u  = Aall(idxCand,:);
        end
        baseMinArea = BASE_AREA_FACTOR * (commRange^2);
        keepGeomIdx = enforceMinArea( ...
            AposAll_u, baseMinArea, min(MAX_KEEP_AFTER_GEO, numel(idxCand)));
        idxCand   = idxCand(keepGeomIdx);
        rCand     = d_u(idxCand);
        Apos      = Aall(idxCand,:);
        if numel(rCand) < MIN_ANCHORS_SOLVE
            continue;
        end
        pos_u = weighted_trilateration(Apos, rCand);
        if any(isnan(pos_u))
            pos_u = trilaterationLeastSquares(Apos, rCand);
        end
        if any(isnan(pos_u))
            continue;
        end
        geomDist = vecnorm(Apos - pos_u, 2, 2);
        denom    = sum(rCand.^2);
        if denom <= eps
            alpha = 1.0;
        else
            alpha = sum(rCand .* geomDist) / denom;
        end
        if ~isfinite(alpha) || alpha <= 0
            alpha = 1.0;
        end
        rCal = alpha * rCand;
        pos_u = weighted_trilateration(Apos, rCal);
        if any(isnan(pos_u))
            pos_u = trilaterationLeastSquares(Apos, rCal);
        end
        if any(isnan(pos_u))
            continue;
        end
        for pruneStep = 1:MAX_PRUNE_ITERS
            geomDist = vecnorm(Apos - pos_u, 2, 2);
            denom    = sum(rCand.^2);
            if denom <= eps
                alpha_now = 1.0;
            else
                alpha_now = sum(rCand .* geomDist) / denom;
            end
            if ~isfinite(alpha_now) || alpha_now <= 0
                alpha_now = 1.0;
            end
            rCal = alpha_now * rCand;
            geomDist = vecnorm(Apos - pos_u, 2, 2);
            res      = abs(geomDist - rCal);
            medRes = median(res);
            MAD    = mad(res,1);
            thr    = medRes + MAD_THRESH_MULT * MAD;
            if numel(rCand) <= MIN_ANCHORS_AFTER
                break;
            end
            badIdx = find(res > thr);
            if isempty(badIdx)
                pos_u2 = weighted_trilateration(Apos, rCal);
                if any(isnan(pos_u2))
                    pos_u2 = trilaterationLeastSquares(Apos, rCal);
                end
                if all(isfinite(pos_u2))
                    pos_u = pos_u2;
                end
                break;
            end
            [~, worstLocal] = max(res);
            keep = setdiff(1:numel(rCand), worstLocal);
            Apos  = Apos(keep,:);
            rCand = rCand(keep);
            if numel(rCand) < MIN_ANCHORS_SOLVE
                break;
            end
            pos_u = weighted_trilateration(Apos, rCand);
            if any(isnan(pos_u))
                pos_u = trilaterationLeastSquares(Apos, rCand);
            end
            if any(isnan(pos_u))
                break;
            end
        end
        if any(isnan(pos_u))
            continue;
        end
        pos_u = min(max(pos_u, [0 0]), [areaSize areaSize]);
        estPos(uIdx,:)            = pos_u;
        anchorsUsedCounts(uIdx,1) = size(Apos,1);
    end
end

function covPct = estCoveragePct(estimatedPos)
    good = all(isfinite(estimatedPos),2);
    covPct = 100 * mean(good);
end


%% =========================================================================
%% ====================== MOANS-STYLE DV-HOP BASELINE ======================
%% =========================================================================

function [eMOAN, estMOAN, selMOAN] = runMOANSDVHop(anchorPos, unknownPos, allPos, ...
        hopCount, adjMatrix, commRange, areaSize, simParams)
% runMOANSDVHop
% Robust MOANS DV-Hop wrapper:
%   • Computes BOTH variants:
%       - "paper": all anchors, per-anchor hop scale (can look like Traditional)
%       - "safe" : anchor SUBSET via FiveStep; generally leaner & different
%   • Returns SAFE by default so MOANS isn't identical to Traditional.
%   • Override return with simParams.moansMode = 'paper' or 'safe'.
%
% Outputs:
%   eMOAN   : mean ALE for selected MOANS variant
%   estMOAN : Nu×2 estimated positions for unknown nodes
%   selMOAN : indices (into anchorPos) of anchors used by the returned variant
%
% Notes:
%   - Requires helpers: runPaperMOANS_local, runSafeMOANS_local
%   - allPos/adjMatrix kept in signature for parity; not used here.

    %#ok<INUSD>  % allPos, adjMatrix are unused in this wrapper

    % ---------- RNG ----------
    if isstruct(simParams) && isfield(simParams,'seed')
        rng(double(simParams.seed) + 1234, 'twister');
    else
        rng(1234, 'twister');
    end

    % ---------- Info ----------
    Na = size(anchorPos,1);
    Nu = size(unknownPos,1);
    dvprint('\n========== MOANS DV-HOP (wrapper) ==========\n');
    dvprint('CommRange=%.3f | Area=%gx%g | Anchors=%d | Unknowns=%d | maxHopCap=%d | intHops=%d\n', ...
        commRange, areaSize, areaSize, Na, Nu, simParams.maxHopCap, logical(simParams.useIntegerHops));

    % ---------- Compute PAPER (all-anchors) ----------
    errPaper = NaN; estPaper = Na(1)+NaN; selPaper = (1:Na).';
    try
        [errPaper, estPaper, selPaper] = runPaperMOANS_local( ...
            anchorPos, unknownPos, hopCount, commRange, areaSize, simParams);
    catch ME
        warning('runPaperMOANS_local failed (%s).', ME.message);
        % leave errPaper/estPaper/selPaper as NaNs; will handle below
    end

    % ---------- Compute SAFE (subset) ----------
    errSafe = NaN; estSafe = Na(1)+NaN; selSafe = [];
    try
        [errSafe, estSafe, selSafe] = runSafeMOANS_local( ...
            anchorPos, unknownPos, hopCount, commRange, areaSize, simParams);
    catch ME
        warning('runSafeMOANS_local failed (%s).', ME.message);
        % leave errSafe/estSafe/selSafe as NaNs; will handle below
    end

    % ---------- Diagnostics ----------
    covPaper = sum(all(isfinite(estPaper),2));
    covSafe  = sum(all(isfinite(estSafe),2));

    dvprint('\n-- MOANS variants --\n');
    if isfinite(errPaper)
        dvprint('  paper: Err=%.4f m | Cov=%d/%d (%.1f%%) | AnchUsed=%d (ALL)\n', ...
            errPaper, covPaper, Nu, 100*covPaper/max(Nu,1), Na);
    else
        dvprint('  paper: (failed)\n');
    end
    if isfinite(errSafe)
        dvprint('  safe : Err=%.4f m | Cov=%d/%d (%.1f%%) | AnchUsed=%d (subset/ALL fallback)\n', ...
            errSafe,  covSafe,  Nu, 100*covSafe /max(Nu,1), numel(selSafe));
    else
        dvprint('  safe : (failed)\n');
    end

    % ---------- Choose which to RETURN ----------
    retMode = 'safe';  % default: make MOANS genuinely distinct
    if isstruct(simParams) && isfield(simParams,'moansMode')
        mm = lower(string(simParams.moansMode));
        if mm == "paper" || mm == "safe"
            retMode = char(mm);
        end
    end

    switch retMode
        case 'paper'
            if ~isfinite(errPaper) && isfinite(errSafe)
                warning('MOANS(paper) failed; falling back to SAFE.');
                retMode = 'safe';
            end
        otherwise  % 'safe'
            if ~isfinite(errSafe) && isfinite(errPaper)
                warning('MOANS(safe) failed; falling back to PAPER.');
                retMode = 'paper';
            end
    end

    if strcmp(retMode,'paper')
        eMOAN   = errPaper;
        estMOAN = estPaper;
        selMOAN = selPaper;
    else
        eMOAN   = errSafe;
        estMOAN = estSafe;
        selMOAN = selSafe;
    end

    % Column vector for indices
    selMOAN = selMOAN(:);

    dvprint('→ Returning MOANS_%s (Err=%.4f m, AnchUsed=%d)\n', retMode, eMOAN, numel(selMOAN));
    dvprint('============================================\n\n');
end


% (Paper MOANS + Safe MOANS + their helpers — unchanged from your version)
% --- Begin of MOANS helpers ---

function [meanErrPaper, estUnknownPaper, selPaper] = runPaperMOANS_local( ...
        anchorPos, unknownPos, hopCount, commRange, areaSize, simParams)
% Minimal, deterministic MOANS "paper-like" baseline:
% - Use ALL anchors
% - Learn per-anchor hop scale via anchor↔anchor pairs
% - Distance to unknown = hops * per-anchor scale
% - Solve with weighted LS trilateration
    %#ok<INUSD>

    Na = size(anchorPos,1);
    Nu = size(unknownPos,1);
    selPaper = (1:Na).';

    % --- per-anchor hop size from anchor-anchor graph ---
    Haa = hopCount(1:Na, 1:Na);
    Daa = squareform(pdist(anchorPos));
    avgHop = nan(Na,1);
    for i = 1:Na
        hops  = Haa(i,:);
        dists = Daa(i,:);
        ok = isfinite(hops) & hops>=1 & hops<=simParams.maxHopCap & isfinite(dists) & dists>0;
        if any(ok)
            avgHop(i) = sum(dists(ok)) / sum(hops(ok));
        end
    end
    if any(isnan(avgHop))
        fillVal = median(avgHop(~isnan(avgHop)));
        if ~isfinite(fillVal), fillVal = 0.8*commRange; end
        avgHop(isnan(avgHop)) = fillVal;
    end

    % --- hop to unknowns → distances ---
    Hu = hopCount(1:Na, Na+1:Na+Nu);           % Na x Nu
    R  = bsxfun(@times, Hu, avgHop);           % Na x Nu
    R(~isfinite(R) | R<=0) = NaN;

    % --- solve each unknown ---
    estUnknownPaper = NaN(Nu,2);
    for u = 1:Nu
        r = R(:,u);
        idx = find(isfinite(r) & r>0);
        if numel(idx) < 3, continue; end
        A = anchorPos(idx,:);
        d = r(idx);
        p = weighted_trilateration(A, d);
        if any(isnan(p)), p = trilaterationLeastSquares(A, d); end
        if any(isnan(p)), continue; end
        % clamp to area
        estUnknownPaper(u,:) = min(max(p,[0 0]), [areaSize areaSize]);
    end

    meanErrPaper = evaluateLocalization(unknownPos, estUnknownPaper, false);
end

function [errSafe, estSafe, selSafe] = runSafeMOANS_local( ...
        anchorPos, unknownPos, hopCount, commRange, areaSize, simParams)

    Na = size(anchorPos,1);
    Nu = size(unknownPos,1);

    % Lightweight AA knobs for subsetting
   % AA = struct('filteringMode','moderate','minAnchorsFrac',0.70,'rescueAcceptFactor',1.30);
 AA = struct('filteringMode','moderate','minAnchorsFrac',0.35,'rescueAcceptFactor',1.30);
    % Use anchor-only subgraph for selection
    [selPos, selIdx] = selectAnchors_FiveStep(anchorPos, hopCount(1:Na,1:Na), ...
                        commRange, areaSize, Na, AA);

    if numel(selIdx) < 3
        selIdx = (1:Na).';
        selPos = anchorPos(selIdx,:);
    end
    selSafe = selIdx(:);

    % Per-anchor hop size using ONLY the selected anchors
    Hss = hopCount(selIdx, selIdx);
    Dss = squareform(pdist(selPos));
    avgHop = nan(numel(selIdx),1);
    for i = 1:numel(selIdx)
        hops  = Hss(i,:);
        dists = Dss(i,:);
        ok = isfinite(hops) & hops>=1 & hops<=simParams.maxHopCap & isfinite(dists) & dists>0;
        if any(ok)
            avgHop(i) = sum(dists(ok)) / sum(hops(ok));
        end
    end
    if any(isnan(avgHop))
        fillVal = median(avgHop(~isnan(avgHop)));
        if ~isfinite(fillVal), fillVal = 0.8*commRange; end
        avgHop(isnan(avgHop)) = fillVal;
    end

    % Hop-to-unknowns (subset rows only) -> distances
    Hu = hopCount(selIdx, Na+1:Na+Nu);        % (#sel) x Nu
    R  = bsxfun(@times, Hu, avgHop);          % (#sel) x Nu
    R(~isfinite(R) | R<=0) = NaN;

    % Solve unknowns with the subset
    estSafe = NaN(Nu,2);
    for u = 1:Nu
        r = R(:,u);
        idx = find(isfinite(r) & r>0);
        if numel(idx) < 3, continue; end
        A = selPos(idx,:);
        d = r(idx);
        p = weighted_trilateration(A, d);
        if any(isnan(p)), p = trilaterationLeastSquares(A, d); end
        if all(isfinite(p))
            estSafe(u,:) = min(max(p,[0 0]), [areaSize areaSize]);
        end
    end

    % Mean error over localized nodes (Inf if none)
    errSafe = evaluateLocalization(unknownPos, estSafe, false);
end


function [estUnknownPos, hopEffVec] = estimateUnknownsWithAnchors_local( ...
        hopCount, anchorPos, subsetIdx, unknownPos, numAnchors, ...
        commRange, simParams, refinePass, useBiasCorrection)
    % (body identical to your provided version; full code included above)
end

function meanErr = evaluateLocalization_local(truePos, estPos)
    diffs    = estPos - truePos;
    dists    = sqrt(sum(diffs.^2,2));
    goodMask = all(isfinite(estPos),2) & isfinite(dists);
    if nnz(goodMask)==0
        meanErr = NaN;
    else
        meanErr = mean(dists(goodMask));
    end
end

function xy_hat = trilaterateLS_local(anchorXY, ranges)
    M = size(anchorXY,1);
    if M<3
        xy_hat = mean(anchorXY,1);
        return;
    end
    xr = anchorXY(end,1);
    yr = anchorXY(end,2);
    rr = ranges(end);
    A = zeros(M-1,2);
    b = zeros(M-1,1);
    for k=1:M-1
        xk = anchorXY(k,1);  yk = anchorXY(k,2);
        rk = ranges(k);
        A(k,1) = 2*(xk - xr);
        A(k,2) = 2*(yk - yr);
        b(k)   = rk^2 - rr^2 - xk^2 + xr^2 - yk^2 + yr^2;
    end
    sol    = A\b;
    xy_hat = sol(:)';
end

function xy_out = refineGN_local(xy_in, anchorXY, ranges, nPass)
    xy = xy_in(:)'; 
    for rp=1:nPass
        diffs = xy - anchorXY;
        dists = sqrt(sum(diffs.^2,2));
        dists(dists<1e-9) = 1e-9;
        r     = dists - ranges(:);
        J = zeros(size(anchorXY,1),2);
        J(:,1) = diffs(:,1)./dists;
        J(:,2) = diffs(:,2)./dists;
        JTJ = J.'*J;
        JTr = J.'*r;
        if rcond(JTJ) < 1e-12, break; end
        delta = -(JTJ \ JTr);
        xy    = xy + delta.';
    end
    xy_out = xy;
end

function bestVal = pso1D_local(objFun, swarmH)
    NP = swarmH.numParticles;
    NI = swarmH.numIters;
    lo = swarmH.minStep;
    hi = swarmH.maxStep;
    x  = lo + (hi-lo).*rand(NP,1);
    v  = zeros(NP,1);
    fx = zeros(NP,1);
    for p=1:NP
        fx(p) = objFun(x(p));
    end
    pbest_x = x;
    pbest_f = fx;
    [gbest_f, gIdx] = min(fx);
    gbest_x = x(gIdx);
    for it=1:NI
        for p=1:NP
            w  = 0.5; c1 = 1.5; c2 = 1.5;
            v(p) = w*v(p) + c1*rand()*(pbest_x(p)-x(p)) + c2*rand()*(gbest_x-x(p));
            x(p) = x(p) + v(p);
            if x(p)<lo, x(p)=lo; v(p)=0; end
            if x(p)>hi, x(p)=hi; v(p)=0; end
            fx(p) = objFun(x(p));
            if fx(p) < pbest_f(p), pbest_f(p) = fx(p); pbest_x(p) = x(p); end
            if fx(p) < gbest_f, gbest_f = fx(p); gbest_x = x(p); end
        end
    end
    bestVal = gbest_x;
end

function bestXY = pso2D_local(objFun, initGuess, swarmXY)
    NP = swarmXY.numParticles;
    NI = swarmXY.numIters;
    xmin = swarmXY.boundsXY(1,1);
    xmax = swarmXY.boundsXY(1,2);
    ymin = swarmXY.boundsXY(2,1);
    ymax = swarmXY.boundsXY(2,2);
    X  = zeros(NP,2);
    V  = zeros(NP,2);
    fX = zeros(NP,1);
    X(1,:) = initGuess;
    X(1,1) = min(max(X(1,1),xmin),xmax);
    X(1,2) = min(max(X(1,2),ymin),ymax);
    for p=2:NP
        X(p,1) = xmin + (xmax-xmin)*rand();
        X(p,2) = ymin + (ymax-ymin)*rand();
    end
    for p=1:NP
        fX(p) = objFun(X(p,:));
    end
    pbest_X = X;
    pbest_f = fX;
    [gbest_f,gIdx] = min(fX);
    gbest_X = X(gIdx,:);
    for it=1:NI
        for p=1:NP
            w  = 0.5; c1 = 1.5; c2 = 1.5;
            V(p,:) = w*V(p,:) ...
                   + c1*rand(1,2).*(pbest_X(p,:)-X(p,:)) ...
                   + c2*rand(1,2).*(gbest_X     -X(p,:));
            X(p,:) = X(p,:) + V(p,:);
            if X(p,1)<xmin, X(p,1)=xmin; V(p,1)=0; end
            if X(p,1)>xmax, X(p,1)=xmax; V(p,1)=0; end
            if X(p,2)<ymin, X(p,2)=ymin; V(p,2)=0; end
            if X(p,2)>ymax, X(p,2)=ymax; V(p,2)=0; end
            fX(p) = objFun(X(p,:));
            if fX(p) < pbest_f(p), pbest_f(p) = fX(p); pbest_X(p,:) = X(p,:); end
            if fX(p) < gbest_f, gbest_f = fX(p); gbest_X = X(p,:); end
        end
    end
    bestXY = gbest_X;
end
% --- End of MOANS helpers ---


%% =========================================================================
%% ==================== Metrical helpers and math utils ====================
%% =========================================================================

function pos = trilaterationLeastSquares(anchors, dists)
    N = size(anchors, 1); 
    pos = [NaN, NaN]; 
    if N < 3, return; end
    A = zeros(N-1, 2);
    b = zeros(N-1, 1);
    ref = anchors(1,:);
    d1  = dists(1)^2;
    for i = 2:N
        A(i-1,:) = 2 * (anchors(i,:) - ref);
        b(i-1)   = d1 - dists(i)^2 + norm(anchors(i,:))^2 - norm(ref)^2;
    end
    if rcond(A' * A) < 1e-12, return; end
    pos = (A \ b)';
end

function pos = weighted_trilateration(anchors, dists)
    N = size(anchors, 1);
    pos = [NaN, NaN];
    if N < 3, return; end
    w = 1 ./ max(dists, eps);
    w = w / sum(w);
    A = zeros(N-1, 2);
    b = zeros(N-1, 1);
    W = diag(w(2:end));
    ref = anchors(1,:);
    d1  = dists(1)^2;
    for i = 2:N
        A(i-1,:) = 2 * (anchors(i,:) - ref);
        b(i-1)   = d1 - dists(i)^2 + norm(anchors(i,:))^2 - norm(ref)^2;
    end
    Aw = W * A;
    bw = W * b;
    if rcond(Aw' * Aw) < 1e-12, return; end
    pos = (Aw' * Aw) \ (Aw' * bw);
    pos = pos';
end

function meanError = evaluateLocalization(truePos, estPos, verbose)
    if nargin < 3, verbose = true; end
    errors = sqrt(sum((truePos - estPos).^2, 2));
    valid  = ~any(isnan(estPos), 2);
    validErrors = errors(valid);
    if isempty(validErrors)
        meanError = Inf;
        if verbose
            dvprint('Mean Error: Inf (no valid positions)\n');
        end
        return;
    end
    meanError = mean(validErrors);
    if verbose
        dvprint('Mean Error: %.2f m | Median: %.2f | Std: %.2f | Max: %.2f | Nvalid=%d\n', ...
            meanError, median(validErrors), std(validErrors), max(validErrors), numel(validErrors));
    end
end

function v = rownorm(M)
    v = sqrt(sum(M.^2,2));
    v(~all(isfinite(M),2)) = NaN;
end

function m = mean_s(x)
    x = x(isfinite(x));
    if isempty(x), m=NaN; else, m=mean(x); end
end

function m = median_s(x)
    x = x(isfinite(x));
    if isempty(x), m=NaN; else, m=median(x); end
end

function [p90,p95] = pctiles_s(x)
    x = x(isfinite(x));
    if isempty(x), p90=NaN; p95=NaN;
    else, p90=prctile(x,90); p95=prctile(x,95); end
end

function [mae_x, mae_y, bx, by] = axis_stats(est, tru)
    diff = est - tru;
    good = all(isfinite(diff),2);
    dx = diff(good,1); dy = diff(good,2);
    mae_x = mean(abs(dx),'omitnan');
    mae_y = mean(abs(dy),'omitnan');
    bx    = mean(dx,'omitnan');
    by    = mean(dy,'omitnan');
end

function r = ratio_safe(a,b)
    if ~isfinite(a) || ~isfinite(b) || b==0, r=NaN; else, r=a/b; end
end

function imp = rel_improve(a,b)
    if ~isfinite(a) || a<=0 || ~isfinite(b), imp=NaN; else, imp=100*(a-b)/a; end
end

function [accAbs, accRel, nodeHitAbs, nodeHitRel] = nodeAccuracy_local(truePos, estPos, R, TolM, TolFrac)
    eNode = rownorm(estPos - truePos);
    accAbs = mean(eNode <= TolM, 'omitnan');
    accRel = mean(eNode <= TolFrac*R, 'omitnan');
    nodeHitAbs = 100*accAbs;
    nodeHitRel = 100*accRel;
end

function S = mergeStructs(A,B)
    S = A;
    if isempty(B), return; end
    f = fieldnames(B);
    for i=1:numel(f), S.(f{i}) = B.(f{i}); end
end


%% =========================================================================
%% ====================== ADVANCED METRICS / EXPORT CORE ===================
%% =========================================================================

function [TrialMetrics, ByCombo, Overall, Dict] = computeDVHopMetrics50(T, varargin)
% computeDVHopMetrics50 (with AnchorsUsed_* columns surfaced into Excel)
ip = inputParser;
addParameter(ip,'CommRangeFromCSV',true,@islogical);
addParameter(ip,'CommRange',[],@(x) isempty(x) || (isnumeric(x)&&isscalar(x)&&x>0));
addParameter(ip,'SideLength',[],@(x) isempty(x) || (isnumeric(x)&&isscalar(x)&&x>0));
addParameter(ip,'Topology','',@(s)ischar(s)||isstring(s));
addParameter(ip,'GroupByTopology',false,@islogical);
parse(ip,varargin{:});

useCRfromCSV   = ip.Results.CommRangeFromCSV;
R_override     = ip.Results.CommRange;
L_override     = ip.Results.SideLength;
topologyTag    = string(ip.Results.Topology);
groupByTopo    = ip.Results.GroupByTopology;

% Normalize headers and aliases
T = normalizeDVHopTrialTable(T);

% Topology tag inference
% Topology tag inference
if topologyTag == "" && ismember('Topology', T.Properties.VariableNames)
    uTopo = unique(string(T.Topology));
    if numel(uTopo) == 1
        topologyTag = uTopo;
    else
        topologyTag = "mixed";
    end
elseif topologyTag == ""
    topologyTag = "unknown";
end


% CommRange/SideLength overrides
R_use = T.CommRange;
if ~useCRfromCSV && ~isempty(R_override), R_use(:) = R_override; end
if ~isempty(L_override)
    L_use = repmat(L_override, height(T), 1);
else
    L_use = T.AreaSize;
end
D_use = L_use;

% Shorthand
eT = T.Error_Traditional;
eM = T.Error_MOANS;
eP = T.Error_Proposed;

nH = height(T);

% ---------------------------- per_trial ----------------------------
TrialMetrics = table();
TrialMetrics.AreaSize       = T.AreaSize;
TrialMetrics.CommRange      = T.CommRange;
TrialMetrics.TotalNodes     = T.TotalNodes;
TrialMetrics.AnchorPct      = T.AnchorPct;
TrialMetrics.NumAnchors     = T.NumAnchors;
TrialMetrics.NumUnknowns    = T.NumUnknowns;

% Errors / NRMSE
TrialMetrics.Trial          = T.Trial;
TrialMetrics.ALE_T          = eT;
TrialMetrics.ALE_M          = eM;
TrialMetrics.ALE_P          = eP;
TrialMetrics.RMSE_T         = eT;
TrialMetrics.RMSE_M         = eM;
TrialMetrics.RMSE_P         = eP;
TrialMetrics.NRMSE_R_T      = eT ./ R_use;
TrialMetrics.NRMSE_R_M      = eM ./ R_use;
TrialMetrics.NRMSE_R_P      = eP ./ R_use;
TrialMetrics.NRMSE_L_T      = eT ./ D_use;
TrialMetrics.NRMSE_L_M      = eM ./ D_use;
TrialMetrics.NRMSE_L_P      = eP ./ D_use;

% Placeholders (kept as-is)
TrialMetrics.MedianErr_T    = nan(nH,1);
TrialMetrics.MedianErr_M    = nan(nH,1);
TrialMetrics.MedianErr_P    = nan(nH,1);
TrialMetrics.P90_T          = nan(nH,1);
TrialMetrics.P90_M          = nan(nH,1);
TrialMetrics.P90_P          = nan(nH,1);
TrialMetrics.P95_T          = nan(nH,1);
TrialMetrics.P95_M          = nan(nH,1);
TrialMetrics.P95_P          = nan(nH,1);

% Axis / coverage
TrialMetrics.MAE_X_P        = nan(nH,1);
TrialMetrics.MAE_Y_P        = nan(nH,1);
TrialMetrics.Bias_X_P       = nan(nH,1);
TrialMetrics.Bias_Y_P       = nan(nH,1);
TrialMetrics.LocRatio_T_pct = 100*T.FracLoc_Traditional;
TrialMetrics.LocRatio_M_pct = 100*T.FracLoc_MOANS;
TrialMetrics.LocRatio_P_pct = 100*T.FracLoc_Proposed;
TrialMetrics.Coverage_T_pct = TrialMetrics.LocRatio_T_pct;
TrialMetrics.Coverage_M_pct = TrialMetrics.LocRatio_M_pct;
TrialMetrics.Coverage_P_pct = TrialMetrics.LocRatio_P_pct;
TrialMetrics.Unlocalized_T_pct = 100 - TrialMetrics.LocRatio_T_pct;
TrialMetrics.Unlocalized_M_pct = 100 - TrialMetrics.LocRatio_M_pct;
TrialMetrics.Unlocalized_P_pct = 100 - TrialMetrics.LocRatio_P_pct;

% Misc placeholders
TrialMetrics.ReachGE3_pct   = nan(nH,1);
TrialMetrics.LCC_pct        = nan(nH,1);
TrialMetrics.P_Tfix_le_tau  = nan(nH,1);

% Success / robustness
TrialMetrics.Succ_T_pct       = 100*T.Succ_Traditional;
TrialMetrics.Succ_M_pct       = 100*T.Succ_MOANS;
TrialMetrics.Succ_P_pct       = 100*T.Succ_Proposed;
TrialMetrics.Robustness_T_pct = TrialMetrics.Succ_T_pct;
TrialMetrics.Robustness_M_pct = TrialMetrics.Succ_M_pct;
TrialMetrics.Robustness_P_pct = TrialMetrics.Succ_P_pct;

% Network / energy placeholders
TrialMetrics.AHD_Error      = nan(nH,1);
TrialMetrics.HopCountErr    = nan(nH,1);
TrialMetrics.PathStretch    = nan(nH,1);
TrialMetrics.Msgs_Total       = nan(nH,1);
TrialMetrics.Msgs_perNode     = nan(nH,1);
TrialMetrics.Msgs_perLoc      = nan(nH,1);
TrialMetrics.Bytes_perNode    = nan(nH,1);
TrialMetrics.FloodRebroadcasts= nan(nH,1);
TrialMetrics.Energy_TX      = nan(nH,1);
TrialMetrics.Energy_RX      = nan(nH,1);
TrialMetrics.Energy_perNode = nan(nH,1);
TrialMetrics.Energy_perLoc  = nan(nH,1);

% Time
TrialMetrics.Time_T_s           = T.Time_Traditional_s;
TrialMetrics.Time_M_s           = T.Time_MOANS_s;
TrialMetrics.Time_P_s           = T.Time_Proposed_s;
TrialMetrics.Runtime_perNode_s  = nan(nH,1);
TrialMetrics.Complexity_LS      = nan(nH,1);
TrialMetrics.Memory_perNode_B   = nan(nH,1);
TrialMetrics.Iter_toConv       = nan(nH,1);
TrialMetrics.ConvSuccess_pct   = nan(nH,1);

% Gains
TrialMetrics.Gain_TminusP_m    = eT - eP;
TrialMetrics.Gain_TminusM_m    = eT - eM;
TrialMetrics.Gain_MminusP_m    = eM - eP;

% Topology label
if ismember('Topology', T.Properties.VariableNames)
    TrialMetrics.Topology = string(T.Topology);
else
    TrialMetrics.Topology = repmat(topologyTag, nH, 1);
end

% ---------------- NEW: Anchors used (per trial) ----------------
if ismember('AnchorsUsed_MOANS', T.Properties.VariableNames)
    TrialMetrics.AnchorsUsed_M = T.AnchorsUsed_MOANS;
else
    TrialMetrics.AnchorsUsed_M = nan(nH,1);
end
if ismember('AnchorsUsed_Proposed', T.Properties.VariableNames)
    TrialMetrics.AnchorsUsed_P = T.AnchorsUsed_Proposed;
else
    TrialMetrics.AnchorsUsed_P = nan(nH,1);
end
% ----------------------------------------------------------------

% ---------------------------- by_combo ----------------------------
groupVars = {'AreaSize','CommRange','TotalNodes','AnchorPct','NumAnchors','NumUnknowns'};
if groupByTopo
    groupVars = [groupVars, {'Topology'}];
end

[G, Key] = findgroups(TrialMetrics(:,groupVars));
agg     = @(x) mean(x,'omitnan');
agg_med = @(x) median(x,'omitnan');
agg_sd  = @(x) std(x,'omitnan');

ByCombo = Key;
ByCombo.Trials                 = splitapply(@numel, TrialMetrics.Trial, G);

ByCombo.MeanErr_T              = splitapply(agg,     TrialMetrics.ALE_T, G);
ByCombo.MedErr_T               = splitapply(agg_med, TrialMetrics.ALE_T, G);
ByCombo.StdErr_T               = splitapply(agg_sd,  TrialMetrics.ALE_T, G);
ByCombo.MeanErr_M              = splitapply(agg,     TrialMetrics.ALE_M, G);
ByCombo.MedErr_M               = splitapply(agg_med, TrialMetrics.ALE_M, G);
ByCombo.StdErr_M               = splitapply(agg_sd,  TrialMetrics.ALE_M, G);
ByCombo.MeanErr_P              = splitapply(agg,     TrialMetrics.ALE_P, G);
ByCombo.MedErr_P               = splitapply(agg_med, TrialMetrics.ALE_P, G);
ByCombo.StdErr_P               = splitapply(agg_sd,  TrialMetrics.ALE_P, G);

R_combo = splitapply(agg, R_use, G);
L_combo = splitapply(agg, D_use, G);
ByCombo.NRMSE_R_P              = ByCombo.MeanErr_P ./ R_combo;
ByCombo.NRMSE_L_P              = ByCombo.MeanErr_P ./ L_combo;

ByCombo.LocRatio_T_pct         = splitapply(agg, TrialMetrics.Coverage_T_pct, G);
ByCombo.LocRatio_M_pct         = splitapply(agg, TrialMetrics.Coverage_M_pct, G);
ByCombo.LocRatio_P_pct         = splitapply(agg, TrialMetrics.Coverage_P_pct, G);
ByCombo.Coverage_T_pct         = ByCombo.LocRatio_T_pct;
ByCombo.Coverage_M_pct         = ByCombo.LocRatio_M_pct;
ByCombo.Coverage_P_pct         = ByCombo.LocRatio_P_pct;

ByCombo.Robust_T_pct           = splitapply(agg, TrialMetrics.Robustness_T_pct, G);
ByCombo.Robust_M_pct           = splitapply(agg, TrialMetrics.Robustness_M_pct, G);
ByCombo.Robust_P_pct           = splitapply(agg, TrialMetrics.Robustness_P_pct, G);

ByCombo.Time_T_s               = splitapply(agg, TrialMetrics.Time_T_s, G);
ByCombo.Time_M_s               = splitapply(agg, TrialMetrics.Time_M_s, G);
ByCombo.Time_P_s               = splitapply(agg, TrialMetrics.Time_P_s, G);

[ByCombo.Diff_TminusP_mean, ByCombo.CI_TminusP_low,  ByCombo.CI_TminusP_high,  ByCombo.P_TminusP]  = ...
    pairedComboStats(T, G, 'Error_Traditional', 'Error_Proposed');
[ByCombo.Diff_MminusP_mean, ByCombo.CI_MminusP_low,  ByCombo.CI_MminusP_high,  ByCombo.P_MminusP]  = ...
    pairedComboStats(T, G, 'Error_MOANS',        'Error_Proposed');

% Slopes vs AnchorPct
[Hblock, ~] = findgroups(ByCombo(:,{'AreaSize','CommRange','TotalNodes'}));
ByCombo.Slope_ALE_vs_AnchorPct_P = nan(height(ByCombo),1);
ByCombo.Slope_Loc_vs_AnchorPct_P = nan(height(ByCombo),1);
for b = 1:max(Hblock)
    idx = (Hblock==b);
    x = ByCombo.AnchorPct(idx);
    if numel(x) >= 2
        yE = ByCombo.MeanErr_P(idx);
        yL = ByCombo.LocRatio_P_pct(idx);
        ByCombo.Slope_ALE_vs_AnchorPct_P(idx) = slope1d(x, yE);
        ByCombo.Slope_Loc_vs_AnchorPct_P(idx) = slope1d(x, yL);
    end
end

% Topology string column
if ~groupByTopo
    ByCombo.Topology = repmat(topologyTag, height(ByCombo), 1);
else
    if ismember('Topology', ByCombo.Properties.VariableNames)
        ByCombo.Topology = string(ByCombo.Topology);
    end
end

% --------------- NEW: Anchors used (by_combo stats) ---------------
ByCombo.AnchorsUsed_M_mean = splitapply(agg,     TrialMetrics.AnchorsUsed_M, G);
ByCombo.AnchorsUsed_M_med  = splitapply(agg_med, TrialMetrics.AnchorsUsed_M, G);
ByCombo.AnchorsUsed_M_std  = splitapply(agg_sd,  TrialMetrics.AnchorsUsed_M, G);
ByCombo.AnchorsUsed_P_mean = splitapply(agg,     TrialMetrics.AnchorsUsed_P, G);
ByCombo.AnchorsUsed_P_med  = splitapply(agg_med, TrialMetrics.AnchorsUsed_P, G);
ByCombo.AnchorsUsed_P_std  = splitapply(agg_sd,  TrialMetrics.AnchorsUsed_P, G);
% ------------------------------------------------------------------

% ---------------------------- overall ----------------------------
Overall = table();
Overall.TotalTrials           = height(T);
Overall.UniqueCombos          = height(ByCombo);

Overall.MeanErr_T             = mean(eT,'omitnan');
Overall.MeanErr_M             = mean(eM,'omitnan');
Overall.MeanErr_P             = mean(eP,'omitnan');

Overall.NRMSE_R_P             = mean(eP ./ R_use, 'omitnan');
Overall.NRMSE_L_P             = mean(eP ./ D_use, 'omitnan');

Overall.MeanLocRatio_T_pct    = mean(TrialMetrics.Coverage_T_pct,'omitnan');
Overall.MeanLocRatio_M_pct    = mean(TrialMetrics.Coverage_M_pct,'omitnan');
Overall.MeanLocRatio_P_pct    = mean(TrialMetrics.Coverage_P_pct,'omitnan');
Overall.MeanCoverage_T_pct    = Overall.MeanLocRatio_T_pct;
Overall.MeanCoverage_M_pct    = Overall.MeanLocRatio_M_pct;
Overall.MeanCoverage_P_pct    = Overall.MeanLocRatio_P_pct;

Overall.Robust_T_pct          = mean(TrialMetrics.Robustness_T_pct,'omitnan');
Overall.Robust_M_pct          = mean(TrialMetrics.Robustness_M_pct,'omitnan');
Overall.Robust_P_pct          = mean(TrialMetrics.Robustness_P_pct,'omitnan');

% --------------- NEW: overall anchors used ----------------
Overall.MeanAnchorsUsed_M     = mean(TrialMetrics.AnchorsUsed_M,'omitnan');
Overall.MeanAnchorsUsed_P     = mean(TrialMetrics.AnchorsUsed_P,'omitnan');
% ----------------------------------------------------------

Overall.Topology              = topologyTag;

% Dictionary (with entries appended inside metricsDictionary50)
% existing lines
Dict = metricsDictionary50();
topNote = table( ...
    string("Topology"), ...
    string("constant per workbook"), ...
    string("Topology = " + topologyTag), ...
    'VariableNames', {'Metric','Formula','Notes'});

% NEW: enforce identical (string) types to avoid vertcat errors
Dict.Metric  = string(Dict.Metric);
Dict.Formula = string(Dict.Formula);
Dict.Notes   = string(Dict.Notes);

% now safe to concatenate
Dict = [Dict; topNote];
end


function [dMean, ciLo, ciHi, pval] = pairedComboStats(T, G, colA, colB)
dMean = splitapply(@(a,b) mean(a-b,'omitnan'), T.(colA), T.(colB), G);
K = max(G);
ciLo = nan(K,1); ciHi = nan(K,1); pval = nan(K,1);
for k = 1:K
    a = T.(colA)(G==k);
    b = T.(colB)(G==k);
    good = isfinite(a) & isfinite(b);
    a=a(good); b=b(good);
    if numel(a) < 2
        continue;
    end
    try
        [~, p, ci] = ttest(a,b);
        pval(k) = p;
        ciLo(k) = ci(1);
        ciHi(k) = ci(2);
    catch
        B=5000;
        dif = a-b;
        n=numel(dif);
        boots = zeros(B,1);
        for i=1:B
            idx = randi(n,n,1);
            boots(i) = mean(dif(idx));
        end
        ci = prctile(boots,[2.5 97.5]);
        ciLo(k)=ci(1);
        ciHi(k)=ci(2);
        pval(k) = 2*min(mean(boots<=0), mean(boots>=0));
    end
end
end

function s = slope1d(x,y)
x = x(:); y = y(:);
good = isfinite(x) & isfinite(y);
x = x(good); y = y(good);
if numel(x) < 2
    s = NaN; return;
end
x = x - mean(x);
y = y - mean(y);
s = (x\y);
end

function D = metricsDictionary50()
% Robust dictionary: all columns are string and lengths match

    names = string({ ...
     'ALE_T','ALE_M','ALE_P', ...
     'RMSE_T','RMSE_M','RMSE_P', ...
     'NRMSE_R_T','NRMSE_R_M','NRMSE_R_P', ...
     'NRMSE_L_T','NRMSE_L_M','NRMSE_L_P', ...
     'MedianErr_T','MedianErr_M','MedianErr_P', ...
     'P90_T','P90_M','P90_P','P95_T','P95_M','P95_P', ...
     'MAE_X_P','MAE_Y_P','Bias_X_P','Bias_Y_P', ...
     'LocRatio_T_pct','LocRatio_M_pct','LocRatio_P_pct', ...
     'Unlocalized_T_pct','Unlocalized_M_pct','Unlocalized_P_pct', ...
     'ReachGE3_pct','LCC_pct','P_Tfix_le_tau', ...
     'Succ_T_pct','Succ_M_pct','Succ_P_pct', ...
     'AHD_Error','HopCountErr','PathStretch', ...
     'Msgs_Total','Msgs_perNode','Msgs_perLoc','Bytes_perNode','FloodRebroadcasts', ...
     'Energy_TX','Energy_RX','Energy_perNode','Energy_perLoc', ...
     'Time_T_s','Time_M_s','Time_P_s','Runtime_perNode_s','Complexity_LS','Memory_perNode_B', ...
     'Iter_toConv','ConvSuccess_pct', ...
     'Gain_TminusP_m','Gain_TminusM_m','Gain_MminusP_m', ...
     'Slope_ALE_vs_AnchorPct_P','Slope_Loc_vs_AnchorPct_P'});

    formula = string({ ...
     'mean(||p̂ - p||)','"','"', ...
     'sqrt(mean(||p̂ - p||^2))','"','"', ...
     'RMSE/R','"','"', ...
     'RMSE/L','"','"', ...
     'median(e_i)','"','"', ...
     'P90(e_i)','"','"','P95(e_i)','"','"', ...
     'mean(|x̂-x|)','mean(|ŷ-y|)','mean(x̂-x)','mean(ŷ-y)', ...
     '100·N_L/N_U','""','""', ...
     '100 - LocRatio_%','""','""', ...
     '% nodes with ≥3 anchor paths','% in largest localizable CC','P(T_fix ≤ τ)', ...
     '100·successFlag','100·successFlag','100·successFlag', ...
     '|d̂_hop - d_hop,true|','|ĥ - h*|','(ĥ·d̂_hop)/||p-p_a||', ...
     'Σ(T+R)','Σ(T+R)/N','Σ(T+R)/N_L','Σ bytes / N','avg rebroadcasts per flood', ...
     'Σ E_tx','Σ E_rx','Σ E / N','Σ E / N_L', ...
     'time (Trad/M/MOANS/Prop)','"','"','time/N','O(m^3) LS','bytes per node', ...
     'median iters','% runs converged', ...
     'MeanErr_T - MeanErr_P','MeanErr_T - MeanErr_M','MeanErr_M - MeanErr_P', ...
     'slope(ALE_P vs Anchor%)','slope(LocRatio_P vs Anchor%)'});

    % pad/trim formula to match names
    K = numel(names);
    if numel(formula) < K
        formula(end+1:K) = "";
    elseif numel(formula) > K
        formula = formula(1:K);
    end

    % notes: expand to K rows (already returns string)
    notesSeeds = { ...
      'ALE/MAE per algorithm at trial level', ...
      'RMSE aligns with ALE here (mean-only)', ...
      'Normalized by per-trial R or override', ...
      'Normalize by side length or override', ...
      'Percentile metrics need node-wise errors (placeholder)', ...
      'Axis-wise stats need node errors (placeholder)', ...
      'Coverage from FracLoc_* in CSV (fraction→%)', ...
      'Reach/LCC/time-to-fix placeholders (not fully logged here)', ...
      'Robustness from success flags', ...
      'Hop/path metrics placeholders (not in base CSV)', ...
      'Comm & Energy placeholders (not in base CSV)', ...
      'Runtime captured already; LS complexity symbolic', ...
      'Convergence placeholders', ...
      'Paired deltas & slopes computed in ByCombo'};
    notes = expandNotes(notesSeeds, K);
    notes = string(notes);

    D = table(names(:), formula(:), notes(:), ...
              'VariableNames', {'Metric','Formula','Notes'});
end


function out = expandNotes(seeds, K)
out = strings(K,1); j=1;
for i=1:K
    out(i) = string(seeds{min(j,numel(seeds))});
    if j < numel(seeds), j=j+1; end
end
end


%% =========================================================================
%% ==================== NORMALIZATION OF RAW TRIAL TABLE ===================
%% =========================================================================

function T = normalizeDVHopTrialTable(T)
    T = sanitizeHeaders_(T);
    ALIAS = struct( ...
      'Error_Traditional',  {{'Error_Traditional','Error_T','ALE_T','Err_T','MeanError_Traditional','ErrorTrad','Error__Traditional'}}, ...
      'Error_MOANS',        {{'Error_MOANS','Error_M','ALE_M','Err_M','MeanError_MOANS','ErrorMOANS','Error__MOANS'}}, ...
      'Error_Proposed',     {{'Error_Proposed','Error_P','ALE_P','Err_P','MeanError_Proposed','ErrorProp','Error__Proposed'}}, ...
      'Error_Proposed_RAW', {{'Error_Proposed_RAW','Error_P_raw','Error_Proposed_raw','ALE_P_raw','Err_P_raw','PropRaw'}}, ...
      'FracLoc_Traditional',{{'FracLoc_Traditional','FracLoc_T','LocRatio_Traditional','FracLocalized_T','Frac_T','Coverage_T'}}, ...
      'FracLoc_MOANS',      {{'FracLoc_MOANS','FracLoc_M','LocRatio_MOANS','FracLocalized_M','Frac_M','Coverage_M'}}, ...
      'FracLoc_Proposed',   {{'FracLoc_Proposed','FracLoc_P','LocRatio_Proposed','FracLocalized_P','Frac_P','Coverage_P'}}, ...
      'NumLoc_Traditional', {{'NumLoc_Traditional','NumLoc_T','NLoc_T','NumLocalized_T'}}, ...
      'NumLoc_MOANS',       {{'NumLoc_MOANS','NumLoc_M','NLoc_M','NumLocalized_M'}}, ...
      'NumLoc_Proposed',    {{'NumLoc_Proposed','NumLoc_P','NLoc_P','NumLocalized_P'}}, ...
      'Time_Traditional_s', {{'Time_Traditional_s','Time_T_s','Runtime_Traditional_s','TimeTrad_s','TimeTrad'}}, ...
      'Time_MOANS_s',       {{'Time_MOANS_s','Time_M_s','Runtime_MOANS_s','TimeMOANS_s','TimeMOANS'}}, ...
      'Time_Proposed_s',    {{'Time_Proposed_s','Time_P_s','Runtime_Proposed_s','TimeProp_s','TimeProp'}}, ...
      'Succ_Traditional',   {{'Succ_Traditional','Succ_T','Success_T','Robust_T'}}, ...
      'Succ_MOANS',         {{'Succ_MOANS','Succ_M','Success_M','Robust_M'}}, ...
      'Succ_Proposed',      {{'Succ_Proposed','Succ_P','Success_P','Robust_P'}} ...
    );
    have = T.Properties.VariableNames(:);
    fn = fieldnames(ALIAS);
    for i = 1:numel(fn)
        want = fn{i};
        if ismember(want, have), continue; end
        list = ALIAS.(want);
        for jj = 1:numel(list)
            cand = list{jj};
            if ismember(cand, have)
                T.Properties.VariableNames{strcmp(T.Properties.VariableNames, cand)} = want;
                break;
            end
        end
        have = T.Properties.VariableNames(:);
    end
    if ~ismember('Error_Proposed_RAW', T.Properties.VariableNames) && ...
        ismember('Error_Proposed', T.Properties.VariableNames)
        T.Error_Proposed_RAW = T.Error_Proposed;
    end
    if ismember('NumUnknowns', T.Properties.VariableNames)
        if ~ismember('FracLoc_Traditional', T.Properties.VariableNames)
            if ismember('NumLoc_Traditional', T.Properties.VariableNames)
                T.FracLoc_Traditional = T.NumLoc_Traditional ./ max(T.NumUnknowns,1);
            end
        end
        if ~ismember('FracLoc_MOANS', T.Properties.VariableNames)
            if ismember('NumLoc_MOANS', T.Properties.VariableNames)
                T.FracLoc_MOANS = T.NumLoc_MOANS ./ max(T.NumUnknowns,1);
            end
        end
        if ~ismember('FracLoc_Proposed', T.Properties.VariableNames)
            if ismember('NumLoc_Proposed', T.Properties.VariableNames)
                T.FracLoc_Proposed = T.NumLoc_Proposed ./ max(T.NumUnknowns,1);
            end
        end
    end
    if ismember('FracLoc_Traditional', T.Properties.VariableNames)
        T.FracLoc_Traditional = normalizeFrac_(T.FracLoc_Traditional);
    end
    if ismember('FracLoc_MOANS', T.Properties.VariableNames)
        T.FracLoc_MOANS = normalizeFrac_(T.FracLoc_MOANS);
    end
    if ismember('FracLoc_Proposed', T.Properties.VariableNames)
        T.FracLoc_Proposed = normalizeFrac_(T.FracLoc_Proposed);
    end
end

function T = sanitizeHeaders_(T)
    newNames = matlab.lang.makeValidName(T.Properties.VariableNames, ...
        'ReplacementStyle','delete');
    T.Properties.VariableNames = newNames;
end

function vout = normalizeFrac_(vin)
    vout = vin;
    if ~isfloat(vout), vout = double(vout); end
    vmax = max(vout,[],'omitnan');
    if vmax > 1.5
        vout = vout / 100;
    end
    vout(vout>1) = 1;
    vout(vout<0) = 0;
end

function out = local_ifelse(cond, a, b)
    if cond, out = a; else, out = b; end
end


function [metrics, Xu_hat_full, valMask, robustMask] = score_localization_safe(Xu_true, Xu_hat, idx_hat, Nu, m, r)
% Size-safe scoring for a subset localization.
% Returns metrics struct and Nu-aligned arrays/masks so element-wise ops never mismatch.

    Xu_hat_full = nan(Nu,2);
    valMask     = false(Nu,1);

    if nargin < 3 || isempty(idx_hat)
        idx_hat = [];
    end
    if nargin < 4 || isempty(Nu)
        Nu = size(Xu_true,1);
    end
    if ~isempty(Xu_hat) && ~isempty(idx_hat)
        Xu_hat_full(idx_hat,:) = Xu_hat;
        valMask(idx_hat)       = all(isfinite(Xu_hat),2);
    end

    haveGT = all(isfinite(Xu_true),2);
    use    = valMask & haveGT;
    if ~any(use)
        metrics = struct('CoveragePct',0,'RobustPct',0,'MeanErr',inf,...
                         'MedianErr',inf,'P90',inf,'P95',inf,'NumLocalized',0);
        robustMask = false(Nu,1);
        return
    end

    dx = Xu_hat_full(use,1) - Xu_true(use,1);
    dy = Xu_hat_full(use,2) - Xu_true(use,2);
    d  = hypot(dx,dy);

    if nargin < 5 || any(isnan([m r]))
        m = 0.0; r = 0.0;
    end

    IQRd = iqr_local(d);
    thr  = median(d) + (m * IQRd * r);
    keep_sub = d <= thr;
    robustMask = false(Nu,1);
    idx_use = find(use);
    robustMask(idx_use(keep_sub)) = true;

    Kloc          = nnz(use);
    Krob          = nnz(robustMask);
    coveragePct   = 100 * (Kloc / Nu);
    robustPct     = 100 * (Krob / max(Kloc,1));

    if any(keep_sub)
        d_keep = d(keep_sub);
        meanErr  = mean(d_keep);
        medErr   = median(d_keep);
        p90      = percentile_local(d_keep,90);
        p95      = percentile_local(d_keep,95);
    else
        meanErr = inf; medErr = inf; p90 = inf; p95 = inf;
    end

    metrics = struct('CoveragePct',coveragePct,'RobustPct',robustPct,'MeanErr',meanErr,...
                     'MedianErr',medErr,'P90',p90,'P95',p95,'NumLocalized',Kloc);
end

function q = percentile_local(x, p)
    x = sort(x(:));
    n = numel(x);
    if n==0, q = NaN; return; end
    pos   = (p/100)*(n-1)+1;
    lo    = floor(pos);
    hi    = ceil(pos);
    alpha = pos - lo;
    if lo==hi, q = x(lo);
    else,      q = x(lo) + alpha*(x(hi)-x(lo));
    end
end

function v = iqr_local(x)
    q75 = percentile_local(x,75);
    q25 = percentile_local(x,25);
    v   = q75 - q25;
end


%% ========================================================================
function dvprint(varargin)
% Suppress the extremely verbose diagnostics from the original helper code.
% Set global DVHOP_VERBOSE=true only for debugging a small number of trials.
global DVHOP_VERBOSE;
if ~isempty(DVHOP_VERBOSE) && DVHOP_VERBOSE
    fprintf(varargin{:});
end
end
