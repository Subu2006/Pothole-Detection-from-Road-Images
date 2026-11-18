% =========================================================================
% FUNCTION: extract_road_roi.m
% Module: Stage 2 - Geometric Road Corridor Region of Interest (ROI) Masking
% Course: ECE443 Digital Image Processing | Academic Task: CA2
%
% Purpose:
%   Generates and applies an adaptive road corridor mask to isolate the
%   navigable roadway and suppress non-road visual clutter (sky, horizon,
%   trees, roadside structures, and overhead signs).
%
% Supported Modes:
%   - 'auto_corridor': Automatically estimates horizon and builds road polygon
%   - 'full_frame'   : Passes full image without cropping (100% road coverage)
%   - 'corridor'     : Uses standardized dashcam trapezoidal corridor
%   - [N x 2] array  : User-defined custom normalized polygon vertices
%
% Inputs:
%   imgRGB   - [H x W x 3] uint8 RGB image
%   roiInput - Character string ('auto_corridor', 'full_frame', 'corridor')
%              OR [N x 2] array of normalized coordinates [x, y] in [0, 1]
%   cfg      - (Optional) Configuration struct from config.m
%
% Outputs:
%   roiMask   - [H x W] logical binary mask (1 inside road, 0 outside)
%   maskedRGB - [H x W x 3] uint8 image with non-road regions zeroed out
% =========================================================================

function [roiMask, maskedRGB] = extract_road_roi(imgRGB, roiInput, cfg)
    [rows, cols, ~] = size(imgRGB);

    % Handle default inputs
    if nargin < 2 || isempty(roiInput)
        if nargin >= 3 && isfield(cfg, 'roiMode')
            roiInput = cfg.roiMode;
        else
            roiInput = 'auto_corridor';
        end
    end

    if ischar(roiInput) || isstring(roiInput)
        switch lower(char(roiInput))
            case 'full_frame'
                roiMask = true(rows, cols);

            case 'auto_corridor'
                % Auto-estimate horizon row: inspect vertical luminance/gradient profile
                if size(imgRGB, 3) == 3
                    gray = rgb2gray(imgRGB);
                else
                    gray = imgRGB;
                end
                
                % Compute row-wise gradient mean to detect road/horizon boundary
                rowGrad = mean(abs(diff(double(gray), 1, 1)), 2);
                % Search for horizon in upper 10% to 45% of image
                minRow = max(1, round(0.10 * rows));
                maxRow = min(rows, round(0.45 * rows));
                [~, horizonIdx] = max(rowGrad(minRow:maxRow));
                horizonRow = (minRow + horizonIdx - 1) / rows;
                horizonRow = max(0.12, min(0.38, horizonRow)); % clamp to valid physical range

                % Perspective corridor widening toward bottom
                autoPoly = [ ...
                    0.00, 1.00; ...
                    0.20, horizonRow; ...
                    0.80, horizonRow; ...
                    1.00, 1.00 ...
                ];
                polyX = autoPoly(:, 1) * cols;
                polyY = autoPoly(:, 2) * rows;
                roiMask = create_poly_mask(polyX, polyY, rows, cols);

            case 'corridor'
                if nargin >= 3 && isfield(cfg, 'roiPolygon')
                    polyNorm = cfg.roiPolygon;
                else
                    polyNorm = [0.00, 1.00; 0.25, 0.15; 0.75, 0.15; 1.00, 1.00];
                end
                polyX = polyNorm(:, 1) * cols;
                polyY = polyNorm(:, 2) * rows;
                roiMask = create_poly_mask(polyX, polyY, rows, cols);

            otherwise
                % Default fallback: full frame
                roiMask = true(rows, cols);
        end
    elseif isnumeric(roiInput) && size(roiInput, 2) == 2
        % Custom polygon coordinates [x, y] in [0, 1]
        polyX = roiInput(:, 1) * cols;
        polyY = roiInput(:, 2) * rows;
        roiMask = create_poly_mask(polyX, polyY, rows, cols);
    else
        roiMask = true(rows, cols);
    end

    % Apply mask across all 3 color channels
    maskedRGB = zeros(size(imgRGB), 'like', imgRGB);
    for c = 1:size(imgRGB, 3)
        channel = imgRGB(:, :, c);
        channel(~roiMask) = 0;
        maskedRGB(:, :, c) = channel;
    end
end

% -------------------------------------------------------------------------
% HELPER: create_poly_mask (Failsafe for poly2mask across all MATLAB releases)
% -------------------------------------------------------------------------
function mask = create_poly_mask(polyX, polyY, rows, cols)
    try
        mask = poly2mask(polyX, polyY, rows, cols);
    catch
        [XGrid, YGrid] = meshgrid(1:cols, 1:rows);
        mask = inpolygon(XGrid, YGrid, polyX, polyY);
    end
end
