function opto_axes = get_optometric_axes(ellipse_t)
    % 1. Extract raw values
    % fit_ellipse uses a clockwise rotation internally.
    % To convert to standard counter-clockwise, we negate the angle.
    phi_ccw = -rad2deg(ellipse_t.phi);
    
    a = ellipse_t.a;
    b = ellipse_t.b;
    
    % 2. Identify which axis is the "Flat" (Long) axis
    % If 'a' is longer, the angle is phi_ccw.
    % If 'b' is longer, the flat axis is 90 degrees away.
    if a >= b
        raw_angle = phi_ccw;
        opto_axes.major_radius = a;
        opto_axes.minor_radius = b;
    else
        raw_angle = phi_ccw + 90;
        opto_axes.major_radius = b;
        opto_axes.minor_radius = a;
    end
    
    % 3. Standardize to Optometric Range (1-180)
    % This mod handles the 150 vs 30 mapping automatically
    major_angle = mod(raw_angle, 180);
    if major_angle <= 0.1, major_angle = 180; end
    
    opto_axes.major_axis_deg = round(major_angle, 1);
    
    % 4. Steep axis is always 90 degrees offset
    minor_angle = mod(major_angle + 90, 180);
    if minor_angle <= 0.1, minor_angle = 180; end
    opto_axes.minor_axis_deg = round(minor_angle, 1);
end