function [flatAngle, steepAngle, rmsError, a_radius, b_radius] = getHarmonicAstigmatism(t_deg, r_vals)
% GETHARMONICASTIGMATISM Fits an ellipse to Placido ring polar data using a 2-theta harmonic expansion.
    if isempty(r_vals)
        flatAngle = NaN; steepAngle = NaN; rmsError = NaN; a_radius = NaN; b_radius = NaN;
        return;
    end

    % Convert raw tracking angles to radians
    t_rad = deg2rad(t_deg);
    
    % Setup the design matrix for R = R0 + A*cos(2*theta) + B*sin(2*theta)
    M = [ones(size(t_rad)), cos(2*t_rad), sin(2*t_rad)];
    
    % Linear least-squares regression
    coeffs = M \ r_vals; 
    
    R0 = coeffs(1);
    A  = coeffs(2);
    B  = coeffs(3);
    
    % Calculate Flat Axis orientation (Maximum radius location)
    flat_angle_rad = 0.5 * atan2(B, A);
    flatAngle = mod(rad2deg(flat_angle_rad), 180);
    
    % Steep Axis is perpendicular
    steepAngle = mod(flatAngle + 90, 180);
    
    % Calculate Ellipse Radii lengths
    amplitude = sqrt(A^2 + B^2);
    a_radius = R0 + amplitude; 
    b_radius = R0 - amplitude; 
    
    % Calculate pure Elliptical RMS Error (Keratoconus metric)
    r_fit = R0 + A*cos(2*t_rad) + B*sin(2*t_rad);
    rmsError = sqrt(mean((r_vals - r_fit).^2));
end
