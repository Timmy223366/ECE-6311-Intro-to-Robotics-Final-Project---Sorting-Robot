clear; clc;

% --- Camera Setup ---
clear('cam'); 
cam = webcam('USB Camera');
disp('Connected to camera');

% --- Arduino + Motor Setup ---
a = arduino(); 
disp('Connected to Arduino.');

topShield = addon(a, 'Adafruit/MotorShieldV2', 'I2CAddress', '0x61');  
bottomShield = addon(a, 'Adafruit/MotorShieldV2', 'I2CAddress', '0x60'); 

% --- Assign Motors ---
M1 = dcmotor(topShield, 1);  % Motor 1
M5 = dcmotor(topShield, 2);  % Motor 5
M3 = dcmotor(topShield, 3);  % Motor 3
M4 = dcmotor(topShield, 4);  % Motor 4
M2 = dcmotor(bottomShield, 1); % Motor 2

% --- LED and Potentiometer Setup ---
ledPin = 'D53';
potPins = {'A8', 'A9', 'A10', 'A11'};  % 4 pots
writeDigitalPin(a, ledPin, 0);

function driveMotor(motor, speed, duration)
    motor.Speed = speed;
    start(motor);
    pause(duration);
    stop(motor);
end

while true

    % ======================================================
    % 0) MENU — ASK USER WHAT THEY WANT TO DO
    % ======================================================
    userInput = input("Press 'm' to capture & sort, 't' for manual control: ", 's');

    % ======================================================
    % 1) MANUAL CONTROL MODE
    % ======================================================
    if strcmpi(userInput, 't')
        disp("🔧 Entering MANUAL CONTROL MODE. Press Ctrl+C to exit.");
        manualControlMode(a, M1, M2, M3, M4, M5, potPins, ledPin);
        continue;
    end

    % ======================================================
    % 2) SORTING REQUESTED
    % ======================================================
    if strcmpi(userInput, 'm')
        disp("📸 Capturing object for sorting...");

        RGB = snapshot(cam);
        I = rgb2hsv(RGB);

        % ---------- FIGURE 1: ORIGINAL IMAGE ----------
        figure(1); clf;
        imshow(RGB);
        title("Original Snapshot (Before Masking)");
        drawnow;

        % ---------------------- COLOR MASKS ----------------------
        redMask = ((I(:,:,1) >= 0.983) | (I(:,:,1) <= 0.083)) & ...
                   (I(:,:,2) >= 0.268 & I(:,:,2) <= 1) & ...
                   (I(:,:,3) >= 0.463 & I(:,:,3) <= 1);

        blueMask = ((I(:,:,1) >= 0.480) & (I(:,:,1) <= 0.780)) & ...
                   (I(:,:,2) >= 0.545 & I(:,:,2) <= 1) & ...
                   (I(:,:,3) >= 0.308 & I(:,:,3) <= 0.908);

        yellowMask = ((I(:,:,1) >= 0.075) & (I(:,:,1) <= 0.175)) & ...
                      (I(:,:,2) >= 0.257 & I(:,:,2) <= 0.857) & ...
                      (I(:,:,3) >= 0.567 & I(:,:,3) <= 1);

        BW = redMask | blueMask | yellowMask;
        maskedRGBImage = RGB;
        maskedRGBImage(repmat(~BW, [1 1 3])) = 0;

        CC = bwconncomp(BW);
        s = regionprops(CC, 'Centroid','Area','BoundingBox');
        s = s([s.Area] >= 50);

        if isempty(s)
            disp("❌ No valid object detected.");
            continue;
        end

        [~, idxLargest] = max([s.Area]);
        obj = s(idxLargest);

        % ---------------------- COLOR ----------------------
        redCount    = nnz(redMask    & BW);
        blueCount   = nnz(blueMask   & BW);
        yellowCount = nnz(yellowMask & BW);

        [~, idxColor] = max([redCount, blueCount, yellowCount]);
        colors = ["Red","Blue","Yellow"];
        detectedColor = colors(idxColor);

        % ---------------------- SHAPE ----------------------
        bbox = obj.BoundingBox;
        w = bbox(3); h = bbox(4);

        if abs(w - h) < 0.2 * max(w,h)
            shapeLabel = "Square-like";
        else
            shapeLabel = "Rectangle-like";
        end

        % ---------------------- AREA ----------------------
        detectedArea = obj.Area;

        % ==============================================================
        % SNAPSHOT PLOT WITH INFORMATION
        % ==============================================================

        % ---------- FIGURE 2: MASKED IMAGE + INFO ----------
        figure(2); clf;
        imshow(maskedRGBImage);
        hold on;

        % Draw centroid
        plot(obj.Centroid(1), obj.Centroid(2), 'm*', 'MarkerSize', 20, 'LineWidth', 2);

        % Draw bounding box
        rectangle('Position', bbox, 'EdgeColor', 'yellow', 'LineWidth', 2);

        % Display text info on the snapshot
        infoText = sprintf("Color: %s\nShape: %s\nArea: %d px", ...
            detectedColor, shapeLabel, round(detectedArea));

        text(20, 40, infoText, ...
            'Color', 'yellow', ...
            'FontSize', 18, ...
            'FontWeight', 'bold', ...
            'FontName','Monospaced');

        %Text saying if object is too big on figure 2
        if(detectedArea > 15000)
            text(225, 300, "OBJECT TOO BIG", ...
            'Color', 'red', ...
            'FontSize', 30, ...
            'FontWeight', 'bold', ...
            'FontName','Monospaced');
        end

        title("Snapshot Analysis (Frozen at moment 'm' pressed)");
        drawnow;

        % ---------------------- SORT ----------------------
        sortObject(detectedColor, shapeLabel, detectedArea, a, M1, M2, M3, M4, M5);

        continue;
    end

end


%% Areas
% Blue:
% 1 Block - 3002 px
% 9 Block - 27808 px

% Red:
% 1 Block - 2622 px
% 4 Block - 12303 px
% 3 Block Long - 9043 px

% Yellow:
% 1 Block - 2850 px
% 4 Block - 11606 px
% 3 Block Long - 8417 px

% 2000 < Small < 8000
% 8000 < Medium < 15000
% 15000 < Large

% 90 Degree position
% Pot (V): 2.47 2.56 0.69 2.61

% Object pickup location
% Pot (V): 2.46 1.91 1.14 3.53

function sortObject(color, shape, area, a, M1, M2, M3, M4, M5)
dirM5 =  1;
dirM4 = -1;
dirM3 = -1;
dirM2 = 1;

    disp("========== SORTING OBJECT ==========");
    disp("Color = " + color);
    disp("Shape = " + shape);
    disp("Area  = " + area);
    disp("====================================");

    % ======================================================
    % 1) CLASSIFY AREA SIZE CATEGORY
    % ======================================================
    if area < 7000
        sizeLabel = "Small";
    elseif area < 15000
        sizeLabel = "Medium";
    else
        sizeLabel = "Large";
    end

    disp("Size category = " + sizeLabel);

    % ======================================================
    % 2) Decision Tree for Sorting
    % ======================================================

    % ================= RED =================
    if color == "Red"

        if shape == "Square-like"
            if sizeLabel == "Small"
                disp("→ RED + SQUARE + SMALL → Bin R1");

                target = [2.46 1.91 1.14 3.53];
                presetPosition = [2.47, 2.56, 0.69, 2.61];
                %Pick up object
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                driveMotor(M1, +0.4, 2.7);

                %Back to preset positionm
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);

                %Drop off object at corresponding location
                %Pot (V): 1.74 3.07 0.38 4.18
                target = [1.74 3.07 0.38 4.18];
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                driveMotor(M1, -0.4, 1.5);

                %Back to preset positionm
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);

            elseif sizeLabel == "Medium"
                disp("→ RED + SQUARE + MEDIUM → Bin R2");

                target = [2.46 1.91 1.14 3.53];
                presetPosition = [2.47, 2.56, 0.69, 2.61];
                %Pick up object
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                driveMotor(M1, +0.4, 1.7);

                %Back to preset positionm
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);

                %Drop off object at corresponding location
                %Pot (V): 2.18 3.57 0.00 4.44
                target = [2.18 3.57 0.00 4.44];
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                driveMotor(M1, -0.4, 1.1);

                %Back to preset positionm
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);

            else
                disp("→ RED + SQUARE + LARGE → Reject area");
                % add movement code here
            end

        else  % Rectangle-like
            if sizeLabel == "Small"
                disp("→ RED + RECTANGLE + SMALL → Bin R3");
                % add movement code here

            elseif sizeLabel == "Medium"
                disp("→ RED + RECTANGLE + MEDIUM → Bin R4");

                target = [2.46 1.91 1.14 3.53];
                presetPosition = [2.47, 2.56, 0.69, 2.61];
                %Pick up object
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                driveMotor(M1, +0.4, 2.7);

                %Back to preset positionm
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);

                %Drop off object at corresponding location
                %Pot (V): 2.80 3.61 0.00 4.22
                target = [2.80 3.61 0.00 4.22];
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                driveMotor(M1, -0.4, 1.5);

                %Back to preset positionm
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);

            else
                disp("→ RED + RECTANGLE + LARGE → Reject area");
                % add movement code here
            end
        end


    % ================= BLUE =================
    elseif color == "Blue"

        if shape == "Square-like"
            if sizeLabel == "Small"
                disp("→ BLUE + SQUARE + SMALL → Bin B1");

                target = [2.46 1.91 1.14 3.53];
                presetPosition = [2.47, 2.56, 0.69, 2.61];
                %Pick up object
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                driveMotor(M1, +0.4, 2.7);

                %Back to preset positionm
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);

                %Drop off object at corresponding location
                %Pot (V): 3.02 2.23 0.70 3.05
                target = [3.02 2.23 0.70 3.05];
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                driveMotor(M1, -0.4, 1.5);

                %Back to preset positionm
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);

            elseif sizeLabel == "Medium"
                disp("→ BLUE + SQUARE + MEDIUM → Bin B2");
                % add movement code here

            else
                disp("→ BLUE + SQUARE + LARGE → Reject area");
                % add movement code here
            end

        else % Rectangle-like
            if sizeLabel == "Small"
                disp("→ BLUE + RECTANGLE + SMALL → Bin B3");
                % add movement code here

            elseif sizeLabel == "Medium"
                disp("→ BLUE + RECTANGLE + MEDIUM → Bin B4");
                % add movement code here

            else
                disp("→ BLUE + RECTANGLE + LARGE → Reject area");
                % add movement code here
            end
        end


    % ================= YELLOW =================
    elseif color == "Yellow"

        if shape == "Square-like"
            if sizeLabel == "Small"
                disp("→ YELLOW + SQUARE + SMALL → Bin Y1");

                target = [2.46 1.91 1.14 3.53];
                presetPosition = [2.47, 2.56, 0.69, 2.61];
                %Pick up object
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                driveMotor(M1, +0.4, 2.7);

                %Back to preset positionm
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);

                %Drop off object at corresponding location
                %Pot (V): 1.96 2.30 0.65 3.26
                target = [1.96 2.30 0.65 3.26];
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                driveMotor(M1, -0.4, 1.5);

                %Back to preset positionm
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);

            elseif sizeLabel == "Medium"
                disp("→ YELLOW + SQUARE + MEDIUM → Bin Y2");
                target = [2.46 1.91 1.14 3.53];
                presetPosition = [2.47, 2.56, 0.69, 2.61];
                %Pick up object
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                driveMotor(M1, +0.4, 1.7);

                %Back to preset positionm
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);
                
                %Drop off object at corresponding location
                %Pot (V): 2.26 2.77 0.37 3.34
                target = [2.26 2.77 0.37 3.34];
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                driveMotor(M1, -0.4, 1.1);

                %Back to preset positionm
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);

            else
                disp("→ YELLOW + SQUARE + LARGE → Reject area");
                % add movement code here
            end

        else % Rectangle-like
            if sizeLabel == "Small"
                disp("→ YELLOW + RECTANGLE + SMALL → Bin Y3");
                % add movement code here

            elseif sizeLabel == "Medium"
                disp("→ YELLOW + RECTANGLE + MEDIUM → Bin Y4");
                
                target = [2.46 1.91 1.14 3.53];
                presetPosition = [2.47, 2.56, 0.69, 2.61];
                %Pick up object
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                driveMotor(M1, +0.4, 2.7);

                %Back to preset positionm
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);
                
                %Drop off object at corresponding location
                %Pot (V): 2.62 2.70 0.44 3.51
                target = [2.62 2.70 0.44 3.51];
                moveToPotVoltage(a, M5, 'A8',  target(1), 0.4*dirM5);
                moveToPotVoltage(a, M4, 'A9',  target(2), 0.4*dirM4);
                moveToPotVoltage(a, M3, 'A10', target(3), 0.4*dirM3);
                moveToPotVoltage(a, M2, 'A11', target(4), 0.4*dirM2);
                driveMotor(M1, -0.4, 1.5);

                %Back to preset positionm
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                moveToPotVoltage(a, M5, 'A8',  2.55, 0.4*dirM5);
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);

            else
                disp("→ YELLOW + RECTANGLE + LARGE → Reject area");
                % add movement code here
            end
        end


    % ================= UNKNOWN =================
    else
        disp("⚠ Unknown color — sending to reject bin");
        % add movement code here
    end

    disp("========== SORT COMPLETE ==========");

end

function manualControlMode(a, M1, M2, M3, M4, M5, potPins, ledPin)

    writeDigitalPin(a, ledPin, 0);
    disp('Type motor commands. Press Ctrl+C to exit manual mode.');

    while true
        cmd = input('Command (q,w,a,s,z,x,e,r,d,f,o): ', 's');

        switch cmd
            case 'o'
                potValues = zeros(1,4);
                for i = 1:4
                    potValues(i) = readVoltage(a, potPins{i});
                end
                fprintf('Pot (V): %.2f %.2f %.2f %.2f\n', potValues);
                % M5, M4, M3, M2

            case 'p'
                disp("Moving to RIGHT-HAND preset position...");

                % Pot order = M5 (A8), M4 (A9), M3 (A10), M2 (A11)
                presetPosition = [2.47, 2.56, 0.69, 2.61];

                dirM5 =  1;
                dirM4 = -1;
                dirM3 = -1;
                dirM2 = 1;

                % Move M2
                moveToPotVoltage(a, M2, 'A11', presetPosition(4), 0.4*dirM2);
                % Move M3
                moveToPotVoltage(a, M3, 'A10', presetPosition(3), 0.4*dirM3);
                % Move M4
                moveToPotVoltage(a, M4, 'A9',  presetPosition(2), 0.4*dirM4);
                % Move M5
                moveToPotVoltage(a, M5, 'A8',  presetPosition(1), 0.4*dirM5);

                disp("Preset position reached!");


            case 'q'
                driveMotor(M1, +0.6, 0.05);
            case 'w'
                driveMotor(M1, -0.6, 0.05);

            case 'a'
                driveMotor(M5, +0.6, 0.05);
            case 's'
                driveMotor(M5, -0.6, 0.05);

            case 'z'
                driveMotor(M3, +0.6, 0.05);
            case 'x'
                driveMotor(M3, -0.6, 0.05);

            case 'e'
                driveMotor(M4, +0.6, 0.05);
            case 'r'
                driveMotor(M4, -0.6, 0.05);

            case 'd'
                driveMotor(M2, +0.6, 0.05);
            case 'f'
                driveMotor(M2, -0.6, 0.05);

            otherwise
                disp('Invalid command.');
        end
    end
end

function moveToPotVoltage(a, motor, potPin, targetVoltage, speed)

    tol = 0.01;     % acceptable final error
    backoff = 0.015; % how far we intentionally move backward to correct overshoot
    settlePause = 0.05;

    % Read initial value
    currentV = readVoltage(a, potPin);

    % --------------------------
    % 1) Move TOWARD target
    % --------------------------
    if currentV < targetVoltage - tol
        direction = 1;
    elseif currentV > targetVoltage + tol
        direction = -1;
    else
        stop(motor);
        return;
    end

    motor.Speed = speed * direction;
    start(motor);

    while true
        currentV = readVoltage(a, potPin);

        % Enter correction stage if we reach target
        if abs(currentV - targetVoltage) <= tol
            break;
        end

        % Detect overshoot
        if direction == 1 && currentV > targetVoltage + tol
            break;
        elseif direction == -1 && currentV < targetVoltage - tol
            break;
        end
    end

    stop(motor);
    pause(settlePause);


    % --------------------------
    % 2) Overshoot CORRECTION
    % --------------------------
    reverseDir = -direction;

    % Move slightly in reverse direction
    motor.Speed = speed * 0.5 * reverseDir; % slower for fine control
    start(motor);

    % Move until we intentionally back off enough
    while true
        currentV = readVoltage(a, potPin);

        if reverseDir == 1
            if currentV >= targetVoltage - backoff
                break;
            end
        elseif reverseDir == -1
            if currentV <= targetVoltage + backoff
                break;
            end
        end
    end

    stop(motor);
    pause(settlePause);


    % --------------------------
    % 3) Fine Tune
    % --------------------------
    currentV = readVoltage(a, potPin);

    if currentV < targetVoltage - tol
        direction = 1;
    elseif currentV > targetVoltage + tol
        direction = -1;
    else
        return; % already in tolerance
    end

    motor.Speed = speed * 0.3 * direction;
    start(motor);

    while abs(readVoltage(a, potPin) - targetVoltage) > tol
        % Keep approaching
    end

    stop(motor);
    pause(settlePause);
end



