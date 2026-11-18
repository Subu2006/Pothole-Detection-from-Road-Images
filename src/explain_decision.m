% =========================================================================
% FUNCTION: explain_decision.m
% Module: Stage 6 - Explainable Decision Engine & Feature Attribution
% Course: ECE443 Digital Image Processing | Academic Task: CA2
%
% Purpose:
%   Provides transparent, human-interpretable reasoning for why a segmented
%   candidate region is classified as a genuine road pothole or rejected as
%   a false anomaly (e.g. shadow, smooth patch, manhole cover, lane crack).
%
% Inputs:
%   featRow - 1-row table or struct containing extracted features
%   cfg     - Configuration struct from config.m
%
% Outputs:
%   isPothole   - Logical flag (true = Pothole, false = Non-Pothole)
%   confidence  - Calibrated confidence percentage [0, 100]%
%   explanation - Text string explaining the physical and textural rationale
%   breakdown   - Struct detailing passes/fails for each rule boundary
% =========================================================================

function [isPothole, confidence, explanation, breakdown] = explain_decision(featRow, cfg)
    % Extract features from table or struct row
    solidity    = featRow.Solidity;
    aspectRatio = featRow.AspectRatio;
    area        = featRow.Area;
    eccentric   = featRow.Eccentricity;
    circularity = featRow.Circularity;
    contrast    = featRow.GLCM_Contrast;
    energy      = featRow.GLCM_Energy;

    if ismember('Contrast_Ratio', featRow.Properties.VariableNames)
        cRatio = featRow.Contrast_Ratio;
    else
        cRatio = 0.15;
    end

    if ismember('Hazard_Severity', featRow.Properties.VariableNames)
        severityStr = char(featRow.Hazard_Severity);
    else
        severityStr = 'Moderate';
    end

    % Threshold constants
    solMax  = 0.90;
    circMin = 0.18;
    aspMax  = 3.20;
    eccMax  = 0.96;
    contMin = 0.40;
    ratMin  = 0.08;
    minArea = 120;

    if nargin >= 2
        if isfield(cfg, 'solidityMaxThreshold'),    solMax  = cfg.solidityMaxThreshold; end
        if isfield(cfg, 'minCircularity'),          circMin = cfg.minCircularity; end
        if isfield(cfg, 'aspectRatioMaxThreshold'), aspMax  = cfg.aspectRatioMaxThreshold; end
        if isfield(cfg, 'maxEccentricity'),         eccMax  = cfg.maxEccentricity; end
        if isfield(cfg, 'contrastMinThreshold'),    contMin = cfg.contrastMinThreshold; end
        if isfield(cfg, 'minContrastRatio'),        ratMin  = cfg.minContrastRatio; end
        if isfield(cfg, 'minAreaPixelsFar'),        minArea = cfg.minAreaPixelsFar; end
    end

    % Rule 1: Shape Compactness & Crack Rejection
    passCircularity = (circularity >= circMin);
    passAspect      = (aspectRatio <= aspMax);
    passEccentric   = (eccentric <= eccMax);
    passShape       = (passCircularity && passAspect && passEccentric);

    % Rule 2: Contour Irregularity (Eroded Cavity Perimeter)
    passSolidity    = (solidity <= solMax);

    % Rule 3: Radiometric Depth & Surface Texture Contrast
    % Genuine physical depression depth or water pool reflectivity
    passContrast    = (cRatio >= ratMin);

    % Rule 4: Scale Bounds (Physical hazard size)
    passArea        = (area >= minArea);

    % Store breakdown
    breakdown.passShape       = passShape;
    breakdown.passSolidity    = passSolidity;
    breakdown.passContrast    = passContrast;
    breakdown.passArea        = passArea;
    breakdown.passCircularity = passCircularity;
    breakdown.passAspect      = passAspect;
    breakdown.passEccentric   = passEccentric;

    % Build Explainable Rationale Strings
    reasons = {};

    if passShape
        reasons{end+1} = sprintf('Shape Compactness [Circ=%.2f, AR=%.2f]: Elliptic cavity (not a linear crack)', ...
            circularity, aspectRatio);
    else
        reasons{end+1} = sprintf('Shape Rejection [Circ=%.2f, AR=%.2f]: High elongation indicates longitudinal crack/line', ...
            circularity, aspectRatio);
    end

    if passSolidity
        reasons{end+1} = sprintf('Solidity (%.2f <= %.2f): Irregular fractured perimeter confirms asphalt erosion', ...
            solidity, solMax);
    else
        reasons{end+1} = sprintf('Solidity (%.2f > %.2f): Smooth convex boundary indicates manhole or artificial road patch', ...
            solidity, solMax);
    end

    if passContrast
        reasons{end+1} = sprintf('Contrast (GLCM=%.2f, Delta=%.1f%%): Significant depth shadow or water reflectivity', ...
            contrast, cRatio * 100);
    else
        reasons{end+1} = sprintf('Contrast (GLCM=%.2f, Delta=%.1f%%): Flat luminance indicates uniform shadow or oil stain', ...
            contrast, cRatio * 100);
    end

    % Confidence Computation
    score = 0;
    if passShape,    score = score + 35; end
    if passSolidity, score = score + 30; end
    if passContrast, score = score + 25; end
    if passArea,     score = score + 10; end

    confidence = min(98.5, max(12.0, score + (1.0 - energy) * 4.0));

    % Final Classification
    isPothole = (passShape && passSolidity && passContrast && passArea);

    if isPothole
        verdict = sprintf('[CONFIRMED POTHOLE] (Confidence: %.1f%%, Severity: %s)', confidence, severityStr);
    else
        if ~passShape
            verdict = sprintf('[REJECTED: ROAD CRACK] (Confidence: %.1f%%)', 100.0 - confidence);
        elseif ~passSolidity
            verdict = sprintf('[REJECTED: MANHOLE/PATCH] (Confidence: %.1f%%)', 100.0 - confidence);
        elseif ~passContrast
            verdict = sprintf('[REJECTED: SHADOW/STAIN] (Confidence: %.1f%%)', 100.0 - confidence);
        else
            verdict = sprintf('[REJECTED: TEXTURE NOISE] (Confidence: %.1f%%)', 100.0 - confidence);
        end
    end

    explanation = sprintf('%s\nRationale: %s', verdict, strjoin(reasons, ' | '));
end
