% =========================================================================
% FUNCTION: segment_pothole.m
% Module: Stage 4 - Multi-Stage Morphological Segmentation Suite
% Course: ECE443 Digital Image Processing | Academic Task: CA2
%
% Purpose:
%   Isolates candidate pothole regions using selectable classical DIP algorithms:
%     1. 'dual_multimodal': Robust multi-cue fusion (dark cavities + water puddles)
%     2. 'dark_cavity'    : Statistical Otsu & depression thresholding (dry roads)
%     3. 'water_puddle'   : Specular sky reflection & muddy depression (wet roads)
%     4. 'sauvola'        : Sauvola local adaptive thresholding
%     5. 'bottom_hat'     : Morphological bottom-hat local depression extraction
%
%   Applies mathematical morphology (closing, opening, hole filling),
%   distance-transform watershed separation for touching candidates, and
%   perspective-scaled area filtering based on vertical road depth.
%
% Inputs:
%   imgCLAHE - [H x W] uint8 CLAHE-enhanced image
%   roiMask  - [H x W] logical road corridor mask
%   cfg      - Configuration struct from config.m
%
% Outputs:
%   binMask    - [H x W] logical cleaned binary candidate mask
%   labeledImg - [H x W] integer matrix of 8-connected labeled components
%   numRegions - Total number of valid connected candidate regions
% =========================================================================

function [binMask, labeledImg, numRegions] = segment_pothole(imgCLAHE, roiMask, cfg)
    [H, W] = size(imgCLAHE);

    if nargin < 2 || isempty(roiMask)
        roiMask = true(H, W);
    end

    % Extract pixel intensities strictly within the active road surface
    roadPixels = imgCLAHE(roiMask);

    if isempty(roadPixels)
        binMask = false(H, W);
        labeledImg = zeros(H, W);
        numRegions = 0;
        return;
    end

    % Default configuration parameters
    segMode = 'dual_multimodal';
    if nargin >= 3 && isfield(cfg, 'segmentationMode')
        segMode = cfg.segmentationMode;
    end

    seRadiusClose = 4;
    seRadiusOpen  = 2;
    seShape       = 'disk';
    if nargin >= 3 && isfield(cfg, 'diskRadiusClose'), seRadiusClose = cfg.diskRadiusClose; end
    if nargin >= 3 && isfield(cfg, 'diskRadiusOpen'),  seRadiusOpen  = cfg.diskRadiusOpen; end
    if nargin >= 3 && isfield(cfg, 'seShape'),         seShape       = cfg.seShape; end

    % Generate Structuring Elements
    try
        switch lower(seShape)
            case 'square'
                seClose = strel('square', max(3, 2 * seRadiusClose + 1));
                seOpen  = strel('square', max(3, 2 * seRadiusOpen + 1));
            case 'diamond'
                seClose = strel('diamond', seRadiusClose);
                seOpen  = strel('diamond', seRadiusOpen);
            otherwise % 'disk'
                seClose = strel('disk', seRadiusClose);
                seOpen  = strel('disk', seRadiusOpen);
        end
    catch
        % Resilient fallback when C++ morphipp builtin is absent
        [Yc, Xc] = ndgrid(-seRadiusClose:seRadiusClose, -seRadiusClose:seRadiusClose);
        diskMaskClose = (Xc.^2 + Yc.^2) <= (seRadiusClose^2);
        [Yo, Xo] = ndgrid(-seRadiusOpen:seRadiusOpen, -seRadiusOpen:seRadiusOpen);
        diskMaskOpen = (Xo.^2 + Yo.^2) <= (seRadiusOpen^2);
        try
            seClose = strel('arbitrary', diskMaskClose);
            seOpen  = strel('arbitrary', diskMaskOpen);
        catch
            seClose = diskMaskClose;
            seOpen  = diskMaskOpen;
        end
    end

    % 1. Core Segmentation Algorithm Execution
    meanRoad = mean(double(roadPixels));
    stdRoad  = std(double(roadPixels));
    try
        otsuLvl = graythresh(roadPixels) * 255;
    catch
        otsuLvl = pure_graythresh(roadPixels) * 255;
    end
    otsuMult = 0.85;
    if nargin >= 3 && isfield(cfg, 'otsuWeight'), otsuMult = cfg.otsuWeight; end

    switch lower(segMode)
        case 'dark_cavity'
            % Classical dark asphalt depression thresholding
            statThresh = meanRoad - 1.30 * stdRoad;
            darkThresh = min(otsuLvl * otsuMult, statThresh);
            darkThresh = max(darkThresh, meanRoad * 0.35);
            rawBinary  = (double(imgCLAHE) < darkThresh) & roiMask;

        case 'water_puddle'
            % Specular sky reflection pools on wet road surface
            puddleThresh = max(190, meanRoad + 1.40 * stdRoad);
            rawBinary    = (double(imgCLAHE) > puddleThresh) & roiMask;

        case 'bottom_hat'
            % Morphological local depression extraction
            try
                bhat = imbothat(imgCLAHE, seClose);
            catch
                bhat = uint8(max(0, meanRoad - double(imgCLAHE)));
            end
            bhatPixels = bhat(roiMask);
            try
                bhatThresh = graythresh(bhatPixels) * 255 * otsuMult;
            catch
                bhatThresh = pure_graythresh(bhatPixels) * 255 * otsuMult;
            end
            rawBinary  = (bhat > max(25, bhatThresh)) & roiMask;

        case 'sauvola'
            % Local adaptive thresholding
            try
                hMean = fspecial('average', [31 31]);
                localMean = imfilter(double(imgCLAHE), hMean, 'replicate');
                localSq   = imfilter(double(imgCLAHE).^2, hMean, 'replicate');
            catch
                hMean = ones(31, 31) / (31 * 31);
                localMean = conv2(double(imgCLAHE), hMean, 'same');
                localSq   = conv2(double(imgCLAHE).^2, hMean, 'same');
            end
            localVar  = max(0, localSq - localMean.^2);
            localStd  = sqrt(localVar);
            % Sauvola formula: T = m * (1 + k * (s / 128 - 1))
            kVal = 0.20;
            T_sauvola = localMean .* (1.0 + kVal * (localStd / 128.0 - 1.0));
            rawBinary = (double(imgCLAHE) < (T_sauvola - 10)) & roiMask;

        case 'dual_multimodal'
            % Multi-modal cue fusion: Detects both dark depressions and reflective puddles
            statDarkThresh = min(meanRoad - 1.30 * stdRoad, otsuLvl * otsuMult);
            statDarkThresh = max(statDarkThresh, meanRoad * 0.35);
            BW_dark = (double(imgCLAHE) < statDarkThresh) & roiMask;

            statBrightThresh = max(190, meanRoad + 1.40 * stdRoad);
            BW_bright = (double(imgCLAHE) > statBrightThresh) & roiMask;

            rawBinary = (BW_dark | BW_bright) & roiMask;

        otherwise
            rawBinary = (double(imgCLAHE) < (otsuLvl * otsuMult)) & roiMask;
    end

    % 2. Morphological Filtering: Opening to sever thin bridges, Closing to bridge fissures
    try
        openedBinary = imopen(rawBinary, seOpen);
        closedBinary = imclose(openedBinary, seClose);
    catch
        % Fallback pure-MATLAB 2D binary morphology via spatial convolution
        if isa(seOpen, 'strel')
            seO_mat = seOpen.Neighborhood;
        else
            seO_mat = double(seOpen);
        end
        if isa(seClose, 'strel')
            seC_mat = seClose.Neighborhood;
        else
            seC_mat = double(seClose);
        end
        eroded = conv2(double(rawBinary), double(seO_mat), 'same') >= (sum(seO_mat(:)) - 1e-5);
        openedBinary = conv2(double(eroded), double(seO_mat), 'same') > 0;
        dilated = conv2(double(openedBinary), double(seC_mat), 'same') > 0;
        closedBinary = conv2(double(dilated), double(seC_mat), 'same') >= (sum(seC_mat(:)) - 1e-5);
    end

    % 3. Binary Hole Filling to restore internal gravel & cavity highlights
    doHoleFill = true;
    if nargin >= 3 && isfield(cfg, 'enableHoleFilling'), doHoleFill = cfg.enableHoleFilling; end
    if doHoleFill
        try
            filledBinary = imfill(closedBinary, 'holes');
        catch
            filledBinary = closedBinary;
        end
    else
        filledBinary = closedBinary;
    end

    % 4. Watershed Distance Separation for Touching Cavities/Puddles
    doWatershed = true;
    if nargin >= 3 && isfield(cfg, 'enableWatershed'), doWatershed = cfg.enableWatershed; end
    if doWatershed && any(filledBinary(:))
        try
            D = -bwdist(~filledBinary);
            D(~filledBinary) = -Inf;
            L = watershed(D);
            cleanedBinary = filledBinary;
            cleanedBinary(L == 0) = false;
        catch
            cleanedBinary = filledBinary;
        end
    else
        cleanedBinary = filledBinary;
    end

    % 5. Perspective-Scaled Connected Component Filtering
    perspScale = true;
    if nargin >= 3 && isfield(cfg, 'perspectiveScaling'), perspScale = cfg.perspectiveScaling; end

    minAreaFar  = 100;
    minAreaNear = 350;
    maxArea     = 50000;
    if nargin >= 3 && isfield(cfg, 'minAreaPixelsFar'),  minAreaFar  = cfg.minAreaPixelsFar; end
    if nargin >= 3 && isfield(cfg, 'minAreaPixelsNear'), minAreaNear = cfg.minAreaPixelsNear; end
    if nargin >= 3 && isfield(cfg, 'maxAreaPixels'),     maxArea     = cfg.maxAreaPixels; end

    binMask = false(H, W);

    try
        CC = bwconncomp(cleanedBinary, 8);
        props = regionprops(CC, 'Area', 'Centroid', 'Eccentricity', 'Solidity');

        for k = 1:CC.NumObjects
            a = props(k).Area;
            yc = props(k).Centroid(2);

            if perspScale
                minAreaAllowed = minAreaFar + (yc / H) * (minAreaNear - minAreaFar);
            else
                minAreaAllowed = 150;
            end

            e = props(k).Eccentricity;
            s = props(k).Solidity;

            if a >= minAreaAllowed && a <= maxArea && e <= 0.98 && s >= 0.35
                binMask(CC.PixelIdxList{k}) = true;
            end
        end

        % 6. 8-Connected Component Labeling
        [labeledImg, numRegions] = bwlabel(binMask, 8);
    catch
        % Pure-MATLAB connected components and regionprops fallback
        [~, numClean, statsClean, pixelIdxs] = pure_bwconncomp(cleanedBinary);
        for k = 1:numClean
            a = statsClean(k).Area;
            yc = statsClean(k).Centroid(2);

            if perspScale
                minAreaAllowed = minAreaFar + (yc / H) * (minAreaNear - minAreaFar);
            else
                minAreaAllowed = 150;
            end

            e = statsClean(k).Eccentricity;
            s = statsClean(k).Solidity;

            if a >= minAreaAllowed && a <= maxArea && e <= 0.98 && s >= 0.35
                binMask(pixelIdxs{k}) = true;
            end
        end
        [labeledImg, numRegions] = pure_bwlabel(binMask);
    end
end

% -------------------------------------------------------------------------
% PURE-MATLAB FALLBACK HELPERS (Zero C++ Builtin Dependencies)
% -------------------------------------------------------------------------
function [labeled, numObjects, statsList, pixelIdxs] = pure_bwconncomp(BW)
    [H, W] = size(BW);
    labeled = zeros(H, W);
    numObjects = 0;
    statsList = struct('Area', {}, 'Centroid', {}, 'Eccentricity', {}, 'Solidity', {}, 'BoundingBox', {});
    pixelIdxs = {};
    
    visited = ~BW;
    for c = 1:W
        for r = 1:H
            if ~visited(r, c)
                numObjects = numObjects + 1;
                maxPts = H * W;
                qR = zeros(maxPts, 1);
                qC = zeros(maxPts, 1);
                head = 1; tail = 1;
                qR(1) = r; qC(1) = c;
                visited(r, c) = true;
                
                while head <= tail
                    cr = qR(head);
                    cc = qC(head);
                    head = head + 1;
                    labeled(cr, cc) = numObjects;
                    
                    for dr = -1:1
                        for dc = -1:1
                            if dr == 0 && dc == 0, continue; end
                            nr = cr + dr;
                            nc = cc + dc;
                            if nr >= 1 && nr <= H && nc >= 1 && nc <= W
                                if ~visited(nr, nc)
                                    visited(nr, nc) = true;
                                    tail = tail + 1;
                                    qR(tail) = nr;
                                    qC(tail) = nc;
                                end
                            end
                        end
                    end
                end
                
                ptsR = qR(1:tail);
                ptsC = qC(1:tail);
                areaVal = tail;
                minR = min(ptsR); maxR = max(ptsR);
                minC = min(ptsC); maxC = max(ptsC);
                bbox = [minC, minR, maxC - minC + 1, maxR - minR + 1];
                centroid = [mean(ptsC), mean(ptsR)];
                
                bbArea = bbox(3) * bbox(4);
                solidityVal = areaVal / max(1, bbArea);
                asp = max(bbox(3), bbox(4)) / max(1, min(bbox(3), bbox(4)));
                eccVal = min(0.99, max(0.0, sqrt(1 - (1 / (asp^2)))));
                
                statsList(numObjects).Area = areaVal;
                statsList(numObjects).Centroid = centroid;
                statsList(numObjects).BoundingBox = bbox;
                statsList(numObjects).Eccentricity = eccVal;
                statsList(numObjects).Solidity = solidityVal;
                pixelIdxs{numObjects} = sub2ind([H, W], ptsR, ptsC);
            end
        end
    end
end

function [labeled, numObjects] = pure_bwlabel(BW)
    [labeled, numObjects, ~, ~] = pure_bwconncomp(BW);
end

function lvlNorm = pure_graythresh(pixels)
    if isempty(pixels)
        lvlNorm = 0.5;
        return;
    end
    counts = histcounts(double(pixels), 0:256);
    p = counts / sum(counts);
    omega = cumsum(p);
    mu = cumsum(p .* (1:256));
    mu_t = mu(end);
    sigma_b_squared = (mu_t * omega - mu).^2 ./ (omega .* (1 - omega) + 1e-10);
    [~, maxIdx] = max(sigma_b_squared);
    lvlNorm = (maxIdx - 1) / 255;
end
