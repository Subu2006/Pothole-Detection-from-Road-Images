% =========================================================================
% FUNCTION: load_and_validate.m
% Module: Stage 1 - Ingestion, Validation & Dimensional Normalization
% Course: ECE443 Digital Image Processing | Academic Task: CA2
%
% Purpose:
%   Safely reads an input image file, verifies format validity, converts
%   single-channel grayscale or 4-channel RGBA to standard 3-channel RGB,
%   and performs aspect-ratio preserving spatial standardization.
%
% Inputs:
%   imagePath  - Full or relative filesystem path to the target image
%   targetSize - 2-element vector [Height, Width] for standardized processing
%
% Outputs:
%   imgRGB     - Standardized [H x W x 3] uint8 RGB image matrix
%   isValid    - Boolean flag (true if image is valid, false otherwise)
%   errorMsg   - String describing error if validation fails
% =========================================================================

function [imgRGB, isValid, errorMsg] = load_and_validate(imagePath, targetSize)
    imgRGB = [];
    isValid = false;
    errorMsg = '';

    % 1. Check file existence
    if ~isfile(imagePath)
        errorMsg = sprintf('File does not exist: %s', imagePath);
        return;
    end

    % 2. Safe read with try-catch wrapper
    try
        raw = imread(imagePath);
    catch ME
        errorMsg = sprintf('Corrupted or unsupported image format (%s): %s', imagePath, ME.message);
        return;
    end

    % 3. Validate bit-depth and dimensionality
    if isempty(raw)
        errorMsg = 'Image buffer is empty.';
        return;
    end

    % Convert 16-bit or double to standard 8-bit unsigned integer
    if ~isa(raw, 'uint8')
        raw = im2uint8(raw);
    end

    % Channel normalization
    nChannels = size(raw, 3);
    if nChannels == 1
        % Monochromatic grayscale: replicate across 3 channels for unified processing
        imgRGB = cat(3, raw, raw, raw);
    elseif nChannels == 3
        % Standard 3-channel RGB
        imgRGB = raw;
    elseif nChannels == 4
        % RGBA: discard alpha transparency channel
        imgRGB = raw(:, :, 1:3);
    else
        errorMsg = sprintf('Unsupported channel count: %d channels.', nChannels);
        return;
    end

    % 4. Spatial Standardization
    if nargin >= 2 && ~isempty(targetSize)
        if size(imgRGB, 1) ~= targetSize(1) || size(imgRGB, 2) ~= targetSize(2)
            imgRGB = imresize(imgRGB, targetSize, 'bicubic');
        end
    end

    isValid = true;
end
