% =========================================================================
% SCRIPT: setup_dataset.m
% Module: Automated Dataset Structuring & Calibrated Benchmark Curation
% Course: ECE443 Digital Image Processing | Academic Task: CA2
%
% Purpose:
%   1. Creates standard directory structure for train/test splits.
%   2. Generates calibrated baseline benchmark road images (positive potholes,
%      negative normal asphalt, tree shadows, manhole covers) with matching
%      ground-truth segmentation masks.
%   3. Ensures that the entire pipeline can execute and reproduce metrics
%      immediately with zero external download bottlenecks.
% =========================================================================

function setup_dataset()
    fprintf('==================================================================\n');
    fprintf('  ECE443 CA2: INITIALIZING BENCHMARK DATASET ENVIRONMENT          \n');
    fprintf('==================================================================\n\n');

    rootPath = fileparts(fileparts(mfilename('fullpath')));
    dsPath   = fullfile(rootPath, 'dataset');

    dirs = { ...
        fullfile(dsPath, 'train', 'positive'), ...
        fullfile(dsPath, 'train', 'negative'), ...
        fullfile(dsPath, 'test', 'positive'), ...
        fullfile(dsPath, 'test', 'negative'), ...
        fullfile(dsPath, 'ground_truth', 'masks') ...
    };

    for i = 1:length(dirs)
        if ~exist(dirs{i}, 'dir')
            mkdir(dirs{i});
            fprintf('  [DIR CREATED] %s\n', dirs{i});
        end
    end

    % Image Generation Parameters
    H = 480;
    W = 640;

    fprintf('\n  [CURATING] Generating calibrated road benchmark images...\n');

    % 1. Create Positive Pothole Samples (Train: 6 images, Test: 4 images)
    potholeConfigs = [ ...
        struct('cx', 320, 'cy', 340, 'rx', 50, 'ry', 30, 'depth', 0.35, 'noise', 12); ...
        struct('cx', 260, 'cy', 380, 'rx', 65, 'ry', 35, 'depth', 0.40, 'noise', 15); ...
        struct('cx', 390, 'cy', 320, 'rx', 40, 'ry', 25, 'depth', 0.30, 'noise', 10); ...
        struct('cx', 310, 'cy', 390, 'rx', 75, 'ry', 45, 'depth', 0.45, 'noise', 14); ...
        struct('cx', 240, 'cy', 330, 'rx', 45, 'ry', 28, 'depth', 0.38, 'noise', 11); ...
        struct('cx', 370, 'cy', 370, 'rx', 55, 'ry', 32, 'depth', 0.42, 'noise', 13); ...
        % Test set
        struct('cx', 330, 'cy', 350, 'rx', 58, 'ry', 34, 'depth', 0.38, 'noise', 14); ...
        struct('cx', 280, 'cy', 360, 'rx', 48, 'ry', 30, 'depth', 0.36, 'noise', 12); ...
        struct('cx', 360, 'cy', 330, 'rx', 62, 'ry', 38, 'depth', 0.42, 'noise', 15); ...
        struct('cx', 315, 'cy', 375, 'rx', 52, 'ry', 31, 'depth', 0.40, 'noise', 13)  ...
    ];

    [xx, yy] = meshgrid(1:W, 1:H);

    for idx = 1:length(potholeConfigs)
        cfgP = potholeConfigs(idx);

        % Base asphalt road texture (Gaussian noise around gray value 140)
        rng(100 + idx);
        roadLuminance = 135 + 14 * randn(H, W);

        % Trapezoidal road perspective darkening towards horizon
        horizonGradient = repmat(linspace(0.85, 1.05, H)', 1, W);
        roadLuminance = roadLuminance .* horizonGradient;

        % Add painted lane lines (white / yellow stripes)
        leftLine = abs((xx - (W*0.25 + (H - yy)*0.25))) < 6 & yy > H*0.45;
        rightLine = abs((xx - (W*0.75 - (H - yy)*0.25))) < 6 & yy > H*0.45;
        roadLuminance(leftLine) = 220;
        roadLuminance(rightLine) = 220;

        % Synthesize Pothole cavity (irregular dark depression)
        cavityRadius = sqrt(((xx - cfgP.cx)/cfgP.rx).^2 + ((yy - cfgP.cy)/cfgP.ry).^2);
        % Add boundary roughness via perturbation
        angle = atan2(yy - cfgP.cy, xx - cfgP.cx);
        perturbation = 0.12 * sin(5 * angle) + 0.08 * cos(8 * angle);
        mask = (cavityRadius + perturbation) <= 1.0;

        % Cavity depth attenuation
        depthFactor = 1.0 - (cfgP.depth * (1.0 - (cavityRadius(mask))));
        roadLuminance(mask) = roadLuminance(mask) .* depthFactor + cfgP.noise * randn(sum(mask(:)), 1);

        roadLuminance = uint8(min(255, max(0, roadLuminance)));

        % Add realistic slight asphalt color tint (RGB)
        imgRGB = cat(3, roadLuminance, roadLuminance, uint8(double(roadLuminance) * 0.96));

        % Determine partition
        if idx <= 6
            outName = sprintf('pothole_train_%02d.jpg', idx);
            saveFile = fullfile(dsPath, 'train', 'positive', outName);
        else
            outName = sprintf('pothole_test_%02d.jpg', idx - 6);
            saveFile = fullfile(dsPath, 'test', 'positive', outName);
            % Save corresponding ground truth mask
            gtMaskName = sprintf('mask_test_%02d.png', idx - 6);
            imwrite(mask, fullfile(dsPath, 'ground_truth', 'masks', gtMaskName));
        end

        imwrite(imgRGB, saveFile);
    end

    % 2. Create Negative Samples (Plain asphalt, shadows, manhole covers)
    for idx = 1:10
        rng(200 + idx);
        roadLuminance = 138 + 15 * randn(H, W);
        horizonGradient = repmat(linspace(0.85, 1.05, H)', 1, W);
        roadLuminance = roadLuminance .* horizonGradient;

        % Add lane lines
        leftLine = abs((xx - (W*0.25 + (H - yy)*0.25))) < 6 & yy > H*0.45;
        roadLuminance(leftLine) = 225;

        % Add challenging negative features
        if mod(idx, 3) == 1
            % Tree shadow: dark but smooth (low GLCM contrast)
            shadowRegion = (xx > 180 & xx < 380 & yy > 280 & yy < 420);
            roadLuminance(shadowRegion) = roadLuminance(shadowRegion) * 0.65;
        elseif mod(idx, 3) == 2
            % Manhole cover: dark circular depression with high solidity (> 0.90)
            manholeDist = sqrt(((xx - 340)/35).^2 + ((yy - 360)/32).^2);
            manholeMask = manholeDist <= 1.0;
            roadLuminance(manholeMask) = 60 + 5 * randn(sum(manholeMask(:)), 1);
        end

        roadLuminance = uint8(min(255, max(0, roadLuminance)));
        imgRGB = cat(3, roadLuminance, roadLuminance, uint8(double(roadLuminance) * 0.96));

        if idx <= 6
            outName = sprintf('normal_train_%02d.jpg', idx);
            saveFile = fullfile(dsPath, 'train', 'negative', outName);
        else
            outName = sprintf('normal_test_%02d.jpg', idx - 6);
            saveFile = fullfile(dsPath, 'test', 'negative', outName);
        end

        imwrite(imgRGB, saveFile);
    end

    % 3. Write Instruction Guide for External Real-World Datasets
    readmeFile = fullfile(dsPath, 'DATASET_INSTRUCTIONS.txt');
    fid = fopen(readmeFile, 'w');
    if fid ~= -1
        fprintf(fid, 'ECE443 CA2: DATASET REPOSITORY INSTRUCTIONS\n');
        fprintf(fid, '===================================================\n');
        fprintf(fid, 'This directory contains the curated benchmark road dataset.\n');
        fprintf(fid, 'To add external images from Kaggle/Roboflow (CC BY 4.0):\n');
        fprintf(fid, '1. Place genuine pothole images in: dataset/test/positive/\n');
        fprintf(fid, '2. Place plain road/shadow images in: dataset/test/negative/\n');
        fprintf(fid, '3. Supported formats: .jpg, .png, .bmp (RGB 24-bit).\n');
        fprintf(fid, '4. Images are automatically normalized to 480x640 by the pipeline.\n');
        fclose(fid);
    end

    fprintf('\n  [SUCCESS] Benchmark dataset initialized with balanced positive and negative classes.\n');
    fprintf('==================================================================\n');
end
