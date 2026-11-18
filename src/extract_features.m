% =========================================================================
% FUNCTION: extract_features.m
% Module: Stage 5 - 12D Geometric, Statistical Texture & Severity Feature Extraction
% Course: ECE443 Digital Image Processing | Academic Task: CA2
%
% Purpose:
%   Quantifies morphological shape, surface textural properties, and
%   calibrated physical dimensions for every candidate connected component.
%
% Features Extracted:
%   1. Area (px)         - Pixel count
%   2. Area_cm2          - Calibrated physical area in cm^2 (perspective-scaled)
%   3. Perimeter (px)    - Boundary perimeter length
%   4. Circularity       - Form factor: (4*pi*Area) / Perimeter^2 in [0, 1]
%   5. Solidity          - Area / ConvexArea (measures contour irregularity)
%   6. Eccentricity      - Elliptic elongation (0 = circle, 1 = line)
%   7. AspectRatio       - MajorAxisLength / MinorAxisLength
%   8. Extent            - Area / BoundingBoxArea
%   9. GLCM_Contrast     - Spatial intensity variations (internal cavity depth)
%  10. GLCM_Energy       - Textural uniformity
%  11. GLCM_Homogeneity  - Textural closeness of elements
%  12. GLCM_Correlation  - Linear spatial gray-level dependence
%  13. Contrast_Ratio    - Relative luminance drop or water reflectivity
%  14. Severity          - Hazard rating: 'Low', 'Moderate', 'Severe', 'Critical'
%
% Inputs:
%   labeledImg   - [H x W] integer matrix of 8-connected labeled regions
%   imgGray      - [H x W] uint8 grayscale image for texture analysis
%   cfg          - Configuration struct from config.m
%
% Outputs:
%   featureTable - MATLAB Table containing descriptors per blob
%   stats        - Struct array from regionprops containing bounding boxes
% =========================================================================

function [featureTable, stats] = extract_features(labeledImg, imgGray, cfg)
    % 1. Geometric Measurements via regionprops with pure-MATLAB fallback
    try
        stats = regionprops(labeledImg, imgGray, ...
            'Area', 'Perimeter', 'BoundingBox', 'Eccentricity', 'Solidity', ...
            'MajorAxisLength', 'MinorAxisLength', 'Centroid', 'Extent', ...
            'MeanIntensity');
    catch
        stats = compute_props_fallback(labeledImg, imgGray);
    end

    numBlobs = length(stats);

    if numBlobs == 0
        featureTable = table();
        return;
    end

    % Preallocate numeric vectors
    areaVals        = zeros(numBlobs, 1);
    areaCm2Vals     = zeros(numBlobs, 1);
    perimVals       = zeros(numBlobs, 1);
    circularityVals = zeros(numBlobs, 1);
    solidityVals    = zeros(numBlobs, 1);
    eccentricity    = zeros(numBlobs, 1);
    aspectRatio     = zeros(numBlobs, 1);
    extentVals      = zeros(numBlobs, 1);
    glcmContrast    = zeros(numBlobs, 1);
    glcmEnergy      = zeros(numBlobs, 1);
    glcmHomogen     = zeros(numBlobs, 1);
    glcmCorrel      = zeros(numBlobs, 1);
    contrastRatio   = zeros(numBlobs, 1);
    severityVals    = cell(numBlobs, 1);

    imgRows = size(imgGray, 1);
    imgCols = size(imgGray, 2);

    % Background road reference intensity for contrast ratio
    bgMask = (labeledImg == 0);
    if any(bgMask(:))
        bgMean = mean(double(imgGray(bgMask)));
    else
        bgMean = 128.0;
    end
    if isnan(bgMean) || bgMean == 0, bgMean = 128.0; end

    % Physical scale parameters
    baseScale = 0.05; % cm per pixel at road level
    if nargin >= 3 && isfield(cfg, 'pixelToCmScale')
        baseScale = cfg.pixelToCmScale;
    end

    for i = 1:numBlobs
        A = stats(i).Area;
        P = stats(i).Perimeter;
        yc = stats(i).Centroid(2);

        areaVals(i)     = A;
        perimVals(i)    = P;
        solidityVals(i) = stats(i).Solidity;
        eccentricity(i) = stats(i).Eccentricity;
        extentVals(i)   = stats(i).Extent;

        % Form factor / Circularity (clamped to [0, 1])
        if P > 0
            C = (4 * pi * A) / (P^2);
        else
            C = 0.0;
        end
        circularityVals(i) = min(1.0, max(0.0, C));

        % Aspect ratio
        if stats(i).MinorAxisLength > 0
            aspectRatio(i) = stats(i).MajorAxisLength / stats(i).MinorAxisLength;
        else
            aspectRatio(i) = 1.0;
        end

        % Calibrated physical area in cm^2 (perspective depth correction)
        % Objects near horizon (low yc) occupy fewer pixels per cm^2 than foreground
        depthFactor = max(0.40, yc / imgRows);
        cmPerPixel = baseScale / depthFactor;
        areaCm2 = A * (cmPerPixel^2);
        areaCm2Vals(i) = areaCm2;

        % Hazard Severity Classification
        if areaCm2 < 250
            severityVals{i} = 'Low';
        elseif areaCm2 < 800
            severityVals{i} = 'Moderate';
        elseif areaCm2 < 2000
            severityVals{i} = 'Severe';
        else
            severityVals{i} = 'Critical';
        end

        % Relative Photometric Contrast Ratio
        I_mean = stats(i).MeanIntensity;
        contrastRatio(i) = abs(bgMean - I_mean) / bgMean;

        % Extract Localized Sub-patch for Textural Analysis
        bb = round(stats(i).BoundingBox);
        rMin = max(1, bb(2));
        rMax = min(imgRows, bb(2) + bb(4) - 1);
        cMin = max(1, bb(1));
        cMax = min(imgCols, bb(1) + bb(3) - 1);

        subPatch = imgGray(rMin:rMax, cMin:cMax);

        % Ensure sub-patch has sufficient pixels for co-occurrence calculation
        if numel(subPatch) >= 16 && (rMax - rMin >= 2) && (cMax - cMin >= 2)
            offsets = [0 1; -1 1; -1 0; -1 -1];
            numLvls = 16;
            if nargin >= 3 && isfield(cfg, 'glcmOffsets'),   offsets = cfg.glcmOffsets; end
            if nargin >= 3 && isfield(cfg, 'glcmNumLevels'), numLvls = cfg.glcmNumLevels; end

            try
                glcm = graycomatrix(subPatch, ...
                    'Offset', offsets, ...
                    'NumLevels', numLvls, ...
                    'Symmetric', true);
                glcmProps = graycoprops(glcm, {'Contrast', 'Energy', 'Homogeneity', 'Correlation'});

                glcmContrast(i) = mean(glcmProps.Contrast);
                glcmEnergy(i)   = mean(glcmProps.Energy);
                glcmHomogen(i)  = mean(glcmProps.Homogeneity);

                corrVal = mean(glcmProps.Correlation);
                if isnan(corrVal)
                    corrVal = 0.0;
                end
                glcmCorrel(i)   = corrVal;
            catch
                subD = double(subPatch);
                glcmContrast(i) = std(subD(:)) / 10.0;
                glcmEnergy(i)   = 0.5;
                glcmHomogen(i)  = 0.5;
                glcmCorrel(i)   = 0.0;
            end
        else
            glcmContrast(i) = 0.0;
            glcmEnergy(i)   = 1.0;
            glcmHomogen(i)  = 1.0;
            glcmCorrel(i)   = 0.0;
        end
    end

    % Construct structured Table
    featureTable = table(areaVals, areaCm2Vals, perimVals, circularityVals, ...
        solidityVals, eccentricity, aspectRatio, extentVals, ...
        glcmContrast, glcmEnergy, glcmHomogen, glcmCorrel, ...
        contrastRatio, severityVals, ...
        'VariableNames', {'Area', 'Area_cm2', 'Perimeter', 'Circularity', ...
        'Solidity', 'Eccentricity', 'AspectRatio', 'Extent', ...
        'GLCM_Contrast', 'GLCM_Energy', 'GLCM_Homogeneity', 'GLCM_Correlation', ...
        'Contrast_Ratio', 'Hazard_Severity'});
end

% -------------------------------------------------------------------------
% PURE-MATLAB REGION PROPERTIES FALLBACK (Zero External Toolbox Builtins)
% -------------------------------------------------------------------------
function stats = compute_props_fallback(labeledImg, imgGray)
    [H, W] = size(labeledImg);
    labels = unique(labeledImg(:));
    labels(labels == 0) = [];
    numBlobs = length(labels);
    
    if numBlobs == 0
        stats = struct('Area', {}, 'Perimeter', {}, 'BoundingBox', {}, ...
            'Eccentricity', {}, 'Solidity', {}, 'MajorAxisLength', {}, 'MinorAxisLength', {}, ...
            'Centroid', {}, 'Extent', {}, 'MeanIntensity', {});
        return;
    end
    
    stats = repmat(struct('Area', 0, 'Perimeter', 0, 'BoundingBox', [0 0 0 0], ...
        'Eccentricity', 0, 'Solidity', 1, 'MajorAxisLength', 0, 'MinorAxisLength', 0, ...
        'Centroid', [0 0], 'Extent', 1, 'MeanIntensity', 0), numBlobs, 1);
        
    for k = 1:numBlobs
        lbl = labels(k);
        idx = find(labeledImg == lbl);
        [r, c] = ind2sub([H, W], idx);
        
        A = length(idx);
        centroid = [mean(c), mean(r)];
        minR = min(r); maxR = max(r);
        minC = min(c); maxC = max(c);
        w = maxC - minC + 1;
        h = maxR - minR + 1;
        bbox = [minC, minR, w, h];
        bbArea = w * h;
        extentVal = A / max(1, bbArea);
        
        I_vals = double(imgGray(idx));
        meanInt = mean(I_vals);
        
        edgePix = 0;
        for pi = 1:A
            pr = r(pi); pc = c(pi);
            if pr == 1 || pr == H || pc == 1 || pc == W || ...
               labeledImg(pr-1, pc) ~= lbl || labeledImg(pr+1, pc) ~= lbl || ...
               labeledImg(pr, pc-1) ~= lbl || labeledImg(pr, pc+1) ~= lbl
                edgePix = edgePix + 1;
            end
        end
        perim = max(1, edgePix);
        
        if A >= 3
            coords = [c - centroid(1), r - centroid(2)];
            covMat = (coords' * coords) / A;
            [~, D] = eig(covMat);
            eigs = sort(diag(D), 'descend');
            majorLen = 4 * sqrt(max(0, eigs(1)));
            minorLen = 4 * sqrt(max(0, eigs(2)));
            ecc = sqrt(1 - max(0, min(1, eigs(2) / max(1e-6, eigs(1)))));
        else
            majorLen = max(w, h);
            minorLen = min(w, h);
            ecc = 0.5;
        end
        
        stats(k).Area = A;
        stats(k).Perimeter = perim;
        stats(k).BoundingBox = bbox;
        stats(k).Eccentricity = min(0.99, max(0.0, ecc));
        stats(k).Solidity = extentVal;
        stats(k).MajorAxisLength = majorLen;
        stats(k).MinorAxisLength = minorLen;
        stats(k).Centroid = centroid;
        stats(k).Extent = extentVal;
        stats(k).MeanIntensity = meanInt;
    end
end
