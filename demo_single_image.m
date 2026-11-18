% =========================================================================
% INTERACTIVE SINGLE-IMAGE DEMONSTRATION SCRIPT: demo_single_image.m
% Project: Explainable Pothole Detection from Road Images
% Course: ECE443 Digital Image Processing | Academic Task: CA2 (30 Marks)
%
% Purpose:
%   Designed for live viva voce evaluation. Allows the student or examiner
%   to select ANY arbitrary test image via an interactive file dialog (or
%   pass a direct file path), process it in under 150 ms, and render the
%   complete multi-stage visual comparison with explainable rationale.
%
% Usage:
%   demo_single_image()                       % Prompts file picker dialog
%   demo_single_image('dataset/test/positive/pothole_test_01.jpg')
% =========================================================================

function demo_single_image(inputImagePath)
    % Initialize configuration
    cfg = config();
    addpath(cfg.srcPath);

    % Handle interactive file selection if path is not provided
    if nargin < 1 || isempty(inputImagePath)
        defaultDir = fullfile(cfg.datasetPath, 'test', 'positive');
        sampleFile = fullfile(defaultDir, 'images.jpg');
        if ~isfile(sampleFile)
            sampleFile = fullfile(defaultDir, 'real_pothole_test_01.jpg');
        end

        % If running non-interactively or in batch mode, fall back to sample image
        if ~feature('ShowFigureWindows') || ~usejava('desktop')
            inputImagePath = sampleFile;
            fprintf('  [BATCH/HEADLESS DETECTED] Defaulting to: %s\n', inputImagePath);
        else
            if ~exist(defaultDir, 'dir'), defaultDir = pwd; end
            [fileName, filePath] = uigetfile( ...
                {'*.jpg;*.jpeg;*.png;*.bmp', 'Road Image Files (*.jpg, *.png, *.bmp)'; ...
                 '*.*', 'All Files (*.*)'}, ...
                'Select Road Image to Inspect for Potholes', defaultDir);
            
            if isequal(fileName, 0)
                fprintf('User cancelled image selection.\n');
                return;
            end
            inputImagePath = fullfile(filePath, fileName);
        end
    end

    fprintf('==================================================================\n');
    fprintf('  ECE443 CA2: LIVE POTHOLE INSPECTION & EXPLAINABILITY ENGINE     \n');
    fprintf('  Target Image: %s\n', inputImagePath);
    fprintf('==================================================================\n');

    % 1. Ingestion & Validation
    tStart = tic;
    [imgRGB, isValid, err] = load_and_validate(inputImagePath, cfg.targetSize);
    if ~isValid
        errordlg(err, 'Image Ingestion Error');
        return;
    end

    % 2. Road ROI Masking
    [roiMask, maskedRGB] = extract_road_roi(imgRGB, cfg.roiMode, cfg);

    % 3. Preprocessing (NTSC Gray + Median Filtering + CLAHE)
    [imgGray, imgFilt, imgCLAHE] = preprocess_image(imgRGB, roiMask, cfg);

    % 4. Morphological Segmentation
    [binMask, labeledImg, numRegions] = segment_pothole(imgCLAHE, roiMask, cfg);

    % 5. Feature Extraction (8D Geometric + GLCM)
    [featureTable, stats] = extract_features(labeledImg, imgGray, cfg);

    % 6. Explainable Decision Engine
    detectedCount = 0;
    detectedIndices = [];
    explanations = {};

    for i = 1:numRegions
        [isPothole, conf, rationale, ~] = explain_decision(featureTable(i, :), cfg);
        if isPothole
            detectedCount = detectedCount + 1;
            detectedIndices(end+1) = i;
            explanations{end+1} = rationale;
        end
    end

    tTotalMs = toc(tStart) * 1000;

    % 7. Interactive Visualization
    fig = figure('Name', 'Live Demonstration: Pothole Diagnostic Inspection', ...
                 'Position', [60, 60, 1260, 700], 'NumberTitle', 'off');

    % (a) Original Input
    subplot(2, 3, 1);
    imshow(imgRGB);
    title('(a) Original Input Image', 'FontSize', 11, 'FontWeight', 'bold');

    % (b) Road Corridor ROI Mask
    subplot(2, 3, 2);
    imshow(maskedRGB);
    title('(b) Road ROI Masking', 'FontSize', 11, 'FontWeight', 'bold');

    % (c) CLAHE Enhanced
    subplot(2, 3, 3);
    imshow(imgCLAHE);
    title('(c) CLAHE Contrast Enhancement', 'FontSize', 11, 'FontWeight', 'bold');

    % (d) Morphological Binary Mask
    subplot(2, 3, 4);
    imshow(binMask);
    title('(d) Binary Morphological Mask', 'FontSize', 11, 'FontWeight', 'bold');

    % (e) Annotated Bounding Box Overlay
    subplot(2, 3, 5);
    imshow(imgRGB); hold on;
    for k = 1:length(detectedIndices)
        idx = detectedIndices(k);
        bb = stats(idx).BoundingBox;
        rectangle('Position', bb, 'EdgeColor', 'r', 'LineWidth', 2.5);
        text(bb(1), max(15, bb(2) - 8), sprintf('POTHOLE #%d', k), ...
            'Color', 'y', 'FontWeight', 'bold', 'FontSize', 9, 'BackgroundColor', 'k');
    end
    hold off;
    if detectedCount > 0
        title(sprintf('(e) %d Pothole(s) Detected (%.0f ms)', detectedCount, tTotalMs), ...
            'FontSize', 11, 'FontWeight', 'bold', 'Color', [0.8 0 0]);
    else
        title(sprintf('(e) Road Clear (No Potholes, %.0f ms)', tTotalMs), ...
            'FontSize', 11, 'FontWeight', 'bold', 'Color', [0 0.6 0]);
    end

    % (f) Feature Radar / Text Explainer
    subplot(2, 3, 6);
    if detectedCount > 0
        pIdx = detectedIndices(1);
        bar([featureTable.Solidity(pIdx), featureTable.AspectRatio(pIdx)/3, ...
             featureTable.GLCM_Contrast(pIdx)/10, featureTable.GLCM_Energy(pIdx)], ...
             'FaceColor', [0.85 0.35 0.2]);
        set(gca, 'XTickLabel', {'Solidity', 'Aspect/3', 'Contrast/10', 'Energy'});
        ylim([0, 1.2]); grid on;
        ylabel('Normalized Metric Value');
        title('(f) Pothole Feature Signature (#1)', 'FontSize', 11, 'FontWeight', 'bold');
    else
        axis off;
        text(0.1, 0.5, 'ROAD SURFACE NORMAL\nNo severe cavities or irregularities detected.', ...
            'FontSize', 12, 'FontWeight', 'bold', 'Color', [0 0.5 0]);
    end

    % Command Window Diagnostics
    fprintf('\n------------------------------------------------------------------\n');
    fprintf('  INSPECTION SUMMARY: %d Pothole(s) Confirmed in %.1f ms\n', detectedCount, tTotalMs);
    fprintf('------------------------------------------------------------------\n');
    for e = 1:length(explanations)
        fprintf('  [POTHOLE #%d]: %s\n', e, explanations{e});
    end
    if detectedCount == 0
        fprintf('  [VERDICT]: Road surface verified normal (no distress identified).\n');
    end
    fprintf('==================================================================\n\n');
end
