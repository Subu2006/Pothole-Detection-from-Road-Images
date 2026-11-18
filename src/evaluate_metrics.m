% =========================================================================
% FUNCTION: evaluate_metrics.m
% Module: Stage 8 - Quantitative Benchmarking & Metric Evaluation Engine
% Course: ECE443 Digital Image Processing | Academic Task: CA2
%
% Purpose:
%   Calculates quantitative statistical metrics from ground-truth and
%   predicted classifications or binary segmentation masks:
%   - True Positives (TP), False Positives (FP), True Negatives (TN), False Negatives (FN)
%   - Precision, Recall (Sensitivity), Specificity, F1-Score
%   - Intersection over Union (IoU / Jaccard Index)
%   - Mean Execution Latency (ms)
%   Exports performance summaries to CSV.
%
% Inputs:
%   yTrue    - Ground truth binary labels (1 = Pothole, 0 = Normal)
%   yPred    - Predicted binary labels (1 = Pothole, 0 = Normal)
%   iouList  - Vector of pixel-level IoU scores across evaluated images
%   latencies- Vector of per-image execution times in milliseconds
%   cfg      - Configuration struct from config.m
%
% Outputs:
%   metricsTable - Summary table containing all calculated metrics
% =========================================================================

function metricsTable = evaluate_metrics(yTrue, yPred, iouList, latencies, cfg)
    % Ensure boolean logical arrays
    yTrue = logical(yTrue(:));
    yPred = logical(yPred(:));

    % 1. Compute Confusion Matrix Elements
    TP = sum(yTrue & yPred);
    FP = sum(~yTrue & yPred);
    TN = sum(~yTrue & ~yPred);
    FN = sum(yTrue & ~yPred);

    totalSamples = length(yTrue);

    % 2. Compute Statistical Performance Metrics
    accuracy = (TP + TN) / max(1, totalSamples);

    if (TP + FP) > 0
        precision = TP / (TP + FP);
    else
        precision = 0.0;
    end

    if (TP + FN) > 0
        recall = TP / (TP + FN);
    else
        recall = 0.0;
    end

    if (TN + FP) > 0
        specificity = TN / (TN + FP);
    else
        specificity = 0.0;
    end

    if (precision + recall) > 0
        f1Score = 2 * (precision * recall) / (precision + recall);
    else
        f1Score = 0.0;
    end

    % 3. Segmentation IoU Metrics
    if nargin >= 3 && ~isempty(iouList)
        meanIoU = mean(iouList);
        stdIoU  = std(iouList);
    else
        meanIoU = NaN;
        stdIoU  = NaN;
    end

    % 4. Execution Latency
    if nargin >= 4 && ~isempty(latencies)
        meanLatencyMs = mean(latencies);
    else
        meanLatencyMs = NaN;
    end

    % 5. Construct Structured Output Table
    metricNames = { ...
        'Total_Samples'; ...
        'True_Positives_TP'; ...
        'False_Positives_FP'; ...
        'True_Negatives_TN'; ...
        'False_Negatives_FN'; ...
        'Accuracy_Percent'; ...
        'Precision_Percent'; ...
        'Recall_Sensitivity_Percent'; ...
        'Specificity_Percent'; ...
        'F1_Score_Percent'; ...
        'Mean_Segmentation_IoU'; ...
        'Mean_Latency_ms' ...
    };

    metricValues = [ ...
        totalSamples; ...
        TP; ...
        FP; ...
        TN; ...
        FN; ...
        accuracy * 100; ...
        precision * 100; ...
        recall * 100; ...
        specificity * 100; ...
        f1Score * 100; ...
        meanIoU; ...
        meanLatencyMs ...
    ];

    metricsTable = table(metricNames, metricValues, 'VariableNames', {'Metric', 'Value'});

    % 6. Export to CSV Spreadsheet
    if nargin >= 5 && isfield(cfg, 'tablePath')
        if ~exist(cfg.tablePath, 'dir'), mkdir(cfg.tablePath); end
        csvOutPath = fullfile(cfg.tablePath, 'performance_summary.csv');
        writetable(metricsTable, csvOutPath);
        fprintf('  [SAVED] Quantitative benchmark exported to: %s\n', csvOutPath);
    end
end
