% =========================================================================
% FUNCTION: preprocess_image.m
% Module: Stage 3 - Radiometric Preprocessing, Denoising & Contrast Enhancement
% Course: ECE443 Digital Image Processing | Academic Task: CA2
%
% Purpose:
%   1. Converts 24-bit RGB to perception-weighted grayscale (ITU-R BT.601).
%   2. Applies selectable edge-preserving denoising (Bilateral, Gaussian,
%      Median, Wiener) to attenuate asphalt speckle noise.
%   3. Applies contrast enhancement (CLAHE, HistEq, Imadjust) to expose
%      low-reflectance depressions and water puddle reflections.
%   4. Computes multi-operator edge detection map (Canny, Sobel, Prewitt, LoG).
%
% Inputs:
%   imgRGB  - [H x W x 3] uint8 RGB image
%   roiMask - [H x W] logical road corridor mask
%   cfg     - Configuration struct from config.m
%
% Outputs:
%   imgGray  - [H x W] uint8 grayscale luminance image
%   imgFilt  - [H x W] uint8 denoised image
%   imgCLAHE - [H x W] uint8 contrast-enhanced image (ROI-masked)
%   imgEdge  - [H x W] logical edge detection feature map
% =========================================================================

function [imgGray, imgFilt, imgCLAHE, imgEdge] = preprocess_image(imgRGB, roiMask, cfg)
    % 1. Perception-weighted Luminance Conversion: Y = 0.2989*R + 0.5870*G + 0.1140*B
    if size(imgRGB, 3) == 3
        try
            imgGray = rgb2gray(imgRGB);
        catch
            imgGray = uint8(0.2989 * double(imgRGB(:,:,1)) + ...
                            0.5870 * double(imgRGB(:,:,2)) + ...
                            0.1140 * double(imgRGB(:,:,3)));
        end
    else
        imgGray = imgRGB;
    end

    if nargin < 2 || isempty(roiMask)
        roiMask = true(size(imgGray));
    end

    % 2. Edge-Preserving Denoising Selection
    filterType = 'gaussian';
    if nargin >= 3 && isfield(cfg, 'filterType')
        filterType = cfg.filterType;
    end

    switch lower(filterType)
        case 'bilateral'
            if exist('imbilatfilt', 'file') == 2
                spSpatial = 2.0;
                spRange = 0.15;
                if isfield(cfg, 'bilateralSigmaSpatial'), spSpatial = cfg.bilateralSigmaSpatial; end
                if isfield(cfg, 'bilateralSigmaRange'), spRange = cfg.bilateralSigmaRange; end
                try
                    imgFilt = imbilatfilt(imgGray, spRange, spSpatial);
                catch
                    imgFilt = pure_gauss_filter(imgGray, [5 5], 1.2);
                end
            else
                try
                    hGauss = fspecial('gaussian', [5 5], 1.2);
                    imgFilt = imfilter(imgGray, hGauss, 'replicate');
                catch
                    imgFilt = pure_gauss_filter(imgGray, [5 5], 1.2);
                end
            end

        case 'gaussian'
            gSize = [5, 5];
            gSigma = 1.2;
            if isfield(cfg, 'gaussFilterSize'), gSize = cfg.gaussFilterSize; end
            if isfield(cfg, 'gaussSigma'), gSigma = cfg.gaussSigma; end
            try
                hGauss = fspecial('gaussian', gSize, gSigma);
                imgFilt = imfilter(imgGray, hGauss, 'replicate');
            catch
                imgFilt = pure_gauss_filter(imgGray, gSize, gSigma);
            end

        case 'median'
            mSize = [3, 3];
            if isfield(cfg, 'medianFilterSize'), mSize = cfg.medianFilterSize; end
            try
                imgFilt = medfilt2(imgGray, mSize);
            catch
                imgFilt = pure_medfilt2(imgGray, mSize);
            end

        case 'wiener'
            wSize = [5, 5];
            if isfield(cfg, 'wienerWindowSize'), wSize = cfg.wienerWindowSize; end
            try
                imgFilt = wiener2(imgGray, wSize);
            catch
                imgFilt = pure_gauss_filter(imgGray, wSize, 1.2);
            end

        otherwise
            imgFilt = imgGray;
    end

    % 3. Contrast Enhancement Selection
    enhType = 'clahe';
    if nargin >= 3 && isfield(cfg, 'enhancementType')
        enhType = cfg.enhancementType;
    end

    switch lower(enhType)
        case 'clahe'
            clipLim = 0.02;
            nTiles = [8, 8];
            distrib = 'uniform';
            if isfield(cfg, 'claheClipLimit'), clipLim = cfg.claheClipLimit; end
            if isfield(cfg, 'claheNumTiles'), nTiles = cfg.claheNumTiles; end
            if isfield(cfg, 'claheDistribution'), distrib = cfg.claheDistribution; end
            try
                imgCLAHE = adapthisteq(imgFilt, ...
                    'ClipLimit', clipLim, ...
                    'NumTiles', nTiles, ...
                    'Distribution', distrib);
            catch
                try
                    imgCLAHE = histeq(imgFilt);
                catch
                    imgCLAHE = imgFilt;
                end
            end

        case 'histeq'
            try
                imgCLAHE = histeq(imgFilt);
            catch
                imgCLAHE = imgFilt;
            end

        case 'imadjust'
            try
                imgCLAHE = imadjust(imgFilt);
            catch
                imgCLAHE = imgFilt;
            end

        case 'none'
            imgCLAHE = imgFilt;

        otherwise
            try
                imgCLAHE = adapthisteq(imgFilt, 'ClipLimit', 0.02, 'NumTiles', [8 8]);
            catch
                imgCLAHE = imgFilt;
            end
    end

    % Restrict enhancement intensity strictly within the active Road ROI
    imgCLAHE(~roiMask) = 0;

    % 4. Multi-Operator Edge Detection Map
    edgeMethod = 'canny';
    if nargin >= 3 && isfield(cfg, 'edgeMethod')
        edgeMethod = cfg.edgeMethod;
    end

    try
        imgEdge = edge(imgCLAHE, edgeMethod) & roiMask;
    catch
        try
            imgEdge = edge(imgCLAHE, 'sobel') & roiMask;
        catch
            % Pure-MATLAB spatial gradient fallback (zero external dependencies)
            Gx = [-1 0 1; -2 0 2; -1 0 1];
            Gy = Gx';
            gx = conv2(double(imgCLAHE), Gx, 'same');
            gy = conv2(double(imgCLAHE), Gy, 'same');
            mag = hypot(gx, gy);
            thresh = 0.15 * max(mag(:));
            imgEdge = (mag > thresh) & roiMask;
        end
    end
end

% -------------------------------------------------------------------------
% PURE-MATLAB FILTERING HELPERS (Zero External IPT Builtins)
% -------------------------------------------------------------------------
function out = pure_gauss_filter(img, gSize, gSigma)
    halfR = floor(gSize(1) / 2);
    halfC = floor(gSize(2) / 2);
    [X, Y] = meshgrid(-halfC:halfC, -halfR:halfR);
    h = exp(-(X.^2 + Y.^2) / (2 * gSigma^2));
    h = h / sum(h(:));
    convResult = conv2(double(img), h, 'same');
    out = uint8(max(0, min(255, round(convResult))));
end

function out = pure_medfilt2(img, mSize)
    [H, W] = size(img);
    padR = floor(mSize(1)/2);
    padC = floor(mSize(2)/2);
    padded = padarray_simple(double(img), padR, padC);
    out = zeros(H, W);
    for r = 1:H
        for c = 1:W
            patch = padded(r:r+2*padR, c:c+2*padC);
            out(r, c) = median(patch(:));
        end
    end
    out = uint8(out);
end

function padded = padarray_simple(img, padR, padC)
    [H, W] = size(img);
    padded = zeros(H + 2*padR, W + 2*padC);
    padded(padR+1:padR+H, padC+1:padC+W) = img;
    % Replicate borders
    padded(1:padR, padC+1:padC+W) = repmat(img(1, :), padR, 1);
    padded(padR+H+1:end, padC+1:padC+W) = repmat(img(end, :), padR, 1);
    padded(:, 1:padC) = repmat(padded(:, padC+1), 1, padC);
    padded(:, padC+W+1:end) = repmat(padded(:, padC+W), 1, padC);
end
