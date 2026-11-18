% =========================================================================
% CONFIGURATION SCRIPT: ECE443 CA2 POTHOLE DETECTION SYSTEM
% Course: ECE443 Digital Image Processing
% Academic Task: CA2 - Projects (30 Marks)
%
% Defines all global hyperparameters, geometric constants, threshold
% limits, and directory structures across the entire MATLAB pipeline.
% Aligned strictly with the ECE443 CA2 Master Project Dossier.
% =========================================================================

function cfg = config()
    % 1. Spatial & Resolution Standardization
    cfg.targetSize = [512, 512];

    % 2. Road Region of Interest (ROI) Modes & Coordinates
    % Modes: 'auto_corridor', 'corridor', 'full_frame', 'interactive'
    cfg.roiMode = 'auto_corridor';
    
    % Default Dashcam Trapezoidal Corridor (Normalized [x, y] in [0, 1])
    cfg.roiPolygon = [ ...
        0.00, 1.00; ... % Bottom-Left
        0.25, 0.15; ... % Top-Left (horizon boundary)
        0.75, 0.15; ... % Top-Right (horizon boundary)
        1.00, 1.00  ... % Bottom-Right
    ];

    % 3. Preprocessing & Denoising Hyperparameters
    cfg.filterType            = 'gaussian';   % 'bilateral', 'gaussian', 'median', 'wiener'
    cfg.medianFilterSize      = [3, 3];
    cfg.gaussFilterSize       = [5, 5];
    cfg.gaussSigma            = 1.2;
    cfg.bilateralSigmaSpatial = 2.0;
    cfg.bilateralSigmaRange   = 0.15;
    cfg.wienerWindowSize      = [5, 5];
    
    % Contrast Enhancement Hyperparameters
    cfg.enhancementType       = 'clahe';      % 'clahe', 'histeq', 'imadjust', 'none'
    cfg.claheClipLimit        = 0.02;         % Normalized contrast clipping factor
    cfg.claheNumTiles         = [8, 8];       % Contextual local tiles
    cfg.claheDistribution     = 'uniform';    % Histogram redistribution profile

    % Edge Detection Hyperparameters
    cfg.edgeMethod            = 'canny';      % 'canny', 'sobel', 'prewitt', 'log'

    % 4. Segmentation Hyperparameters
    % Modes:
    %   'dual_multimodal': Detects both dry dark cavities and wet reflective puddles
    %   'dark_cavity': Dry asphalt depressions (Statistical Otsu + Depth)
    %   'water_puddle': Specular sky reflection pools on wet road
    %   'bottom_hat': Morphological black top-hat depression extraction
    %   'sauvola': Sauvola local adaptive contrast thresholding
    cfg.segmentationMode      = 'dual_multimodal';
    
    % Morphological Structuring Elements
    cfg.seShape               = 'disk';       % 'disk', 'square', 'diamond'
    cfg.diskRadius            = 4;            % Structuring element radius for closing
    cfg.diskRadiusClose       = 4;            % Structuring element radius for closing
    cfg.diskRadiusOpen        = 2;            % Structuring element radius for opening
    cfg.enableHoleFilling     = true;         % Binary hole-filling to restore cavity interior
    cfg.enableWatershed       = true;         % Watershed distance transform to separate touching puddles

    % Area Thresholding (Perspective-Scaled)
    cfg.perspectiveScaling    = true;         % Adapt min area based on vertical perspective row depth
    cfg.minAreaPixelsFar      = 100;          % Minimum area for distant potholes near horizon
    cfg.minAreaPixelsNear     = 350;          % Minimum area for close potholes near vehicle hood
    cfg.minAreaPixels         = 200;          % Default nominal minimum area
    cfg.maxAreaPixels         = 50000;        % Suppress massive whole-road illumination blobs
    cfg.otsuWeight            = 0.80;         % Multiplier on Otsu threshold

    % 5. Feature Extraction & Physical Geometry Calibration
    cfg.glcmOffsets           = [0 1; -1 1; -1 0; -1 -1];
    cfg.glcmNumLevels         = 16;           % Gray-level quantization bins
    cfg.pixelToCmScale        = 0.05;         % Nominal ground resolution: 0.05 cm/pixel at road surface

    % 6. Decision Rules & Thresholds (Explainable Attributions)
    cfg.minCircularity        = 0.18;         % Distinguishes potholes from long road cracks
    cfg.maxEccentricity       = 0.96;         % Potholes are compact/elliptical (< 0.96)
    cfg.minContrastRatio      = 0.08;         % Relative cavity luminance drop or water contrast
    cfg.solidityMaxThreshold  = 0.90;         % Irregular cavity contour (Solidity <= 0.90)
    cfg.contrastMinThreshold  = 0.40;         % Internal depth/texture threshold
    cfg.aspectRatioMaxThreshold = 3.20;       % Rejects continuous longitudinal road cracks

    % Hazard Severity Classification Thresholds (Estimated physical area in cm^2)
    cfg.severityThresholds    = struct( ...
        'low',      250, ...                  % < 250 cm^2: Minor surface raveling
        'moderate', 800, ...                  % 250 - 800 cm^2: Intermediate cavity
        'severe',   2000 ...                  % 800 - 2000 cm^2: Deep cavity (wheel hazard)
    );                                        % >= 2000 cm^2: Critical chassis/axle hazard

    % 7. Active Classifier Engine
    cfg.activeClassifier      = 'tree';       % 'tree', 'svm', 'knn', 'rule_engine'

    % 8. Directory & File Paths (Dynamically relative to project root)
    rootPath = fileparts(mfilename('fullpath'));
    cfg.rootPath    = rootPath;
    cfg.datasetPath = fullfile(rootPath, 'dataset');
    cfg.srcPath     = fullfile(rootPath, 'src');
    cfg.modelsPath  = fullfile(rootPath, 'models');
    cfg.modelPath   = fullfile(rootPath, 'models', 'trained_model.mat');
    cfg.resultsPath = fullfile(rootPath, 'results');
    cfg.figPath     = fullfile(rootPath, 'results', 'figures');
    cfg.tablePath   = fullfile(rootPath, 'results', 'tables');
    cfg.logPath     = fullfile(rootPath, 'results', 'logs');

    % 9. Camera & Real-Time Stream Engine Settings
    cfg.streamEngine  = 'auto'; % 'webcam', 'videoinput', 'videoreader', 'auto'
    cfg.streamFpsCap  = 20.0;   % Target interactive inspection FPS cap

    % 10. Automatic Environment & Toolbox Self-Healing
    if exist(cfg.srcPath, 'dir') && ~contains(path, cfg.srcPath)
        addpath(cfg.srcPath);
    end
    userProfile = getenv('USERPROFILE');
    tbDir = fullfile(userProfile, 'MATLAB_Toolboxes', 'R2026b');
    if strcmpi(matlabroot, tbDir)
        if ~exist('poly2mask', 'file')
            addpath(fullfile(tbDir, 'toolbox', 'images', 'images'));
            addpath(fullfile(tbDir, 'toolbox', 'images', 'iptutils'));
            addpath(fullfile(tbDir, 'toolbox', 'images', 'imdata'));
            addpath(fullfile(tbDir, 'toolbox', 'images', 'colorspaces'));
        end
        if ~exist('fitctree', 'file')
            addpath(fullfile(tbDir, 'toolbox', 'stats', 'classreg'));
            addpath(fullfile(tbDir, 'toolbox', 'stats', 'stats'));
            addpath(fullfile(tbDir, 'toolbox', 'shared', 'statslib'));
        end
    end
end
