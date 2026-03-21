#version 300 es

precision mediump float;

layout(location = 0) out highp vec4 FragColor;

uniform sampler2D u_bufferA;
uniform sampler2D u_restir_buffer;
uniform sampler2D u_restir_aux;
uniform sampler2D u_restir_history1;
uniform sampler2D u_restir_history1_aux;
uniform sampler2D u_restir_history2;
uniform sampler2D u_restir_history2_aux;
uniform float u_cont;
uniform vec2 u_resolution;
uniform uint u_frame;

const vec3 gamma = vec3(1./2.2);

// Helper function to unpack reservoir aux data
vec3 unpackReservoirAuxDebug(vec4 aux_data) {
    // RGB contains light_color, A contains packed (age, M, light_index)
    float packed_alpha = aux_data.w;
    float normalized_light_index = fract(packed_alpha * 2.94);
    float temp = packed_alpha - normalized_light_index * 0.34;
    float normalized_M = fract(temp * 3.03);
    float normalized_age = (temp - normalized_M * 0.33) * 3.03;
    
    // Denormalize
    float age = normalized_age * 30.0; // MAX_RESERVOIR_AGE = 30
    float M = normalized_M * 100.0;
    int light_index = int(normalized_light_index * 16.0) - 1; // Assume max 16 lights
    
    return vec3(age, M, float(light_index));
}

// Validate reservoir data for debugging (more lenient)
bool isValidReservoirDebug(vec4 main_data, vec4 aux_data) {
    // More lenient validation to show more data
    if (main_data.w <= 0.0) return false; // No weight
    if (length(aux_data.rgb) <= 0.0001) return false; // No light color (more lenient)
    
    vec3 debug_data = unpackReservoirAuxDebug(aux_data);
    float age = debug_data.x;
    float M = debug_data.y;
    float light_idx = debug_data.z;
    
    // Much more lenient validation ranges
    if (age < 0.0 || age > 100.0) return false; // Wider age range
    if (M < 0.1 || M > 300.0) return false; // Wider M range
    if (light_idx < -1.0 || light_idx > 50.0) return false; // Wider light index range
    
    return true;
}

// Calculate ReSTIR effectiveness metric
float calculateReSTIREffectiveness(vec4 current_data, vec4 current_aux, vec4 history_data, vec4 history_aux) {
    if (!isValidReservoirDebug(current_data, current_aux)) return -1.0;
    
    vec3 current_debug = unpackReservoirAuxDebug(current_aux);
    float current_weight = current_data.w;
    float current_M = current_debug.y;
    
    // Base effectiveness from weight and sample count
    float base_effectiveness = clamp(current_weight * sqrt(current_M) / 8.0, 0.0, 1.0);
    
    // Temporal improvement factor
    float temporal_factor = 1.0;
    if (isValidReservoirDebug(history_data, history_aux)) {
        vec3 history_debug = unpackReservoirAuxDebug(history_aux);
        float history_weight = history_data.w;
        float history_M = history_debug.y;
        
        if (history_weight > 0.001 && history_M > 0.5) {
            // Calculate improvement ratio
            float weight_improvement = current_weight / history_weight;
            float sample_improvement = current_M / history_M;
            temporal_factor = sqrt(weight_improvement * sample_improvement);
            temporal_factor = clamp(temporal_factor, 0.5, 2.0);
        }
    }
    
    return base_effectiveness * temporal_factor;
}

void main(){
    vec2 uv = gl_FragCoord.xy / u_resolution;
    float gridX = 1.0 / 3.0; // 3 columns
    float gridY = 1.0 / 3.0; // 3 rows for more comprehensive debugging
    
    int colIndex = int(uv.x / gridX);
    int rowIndex = int(uv.y / gridY);
    
    vec2 cellUV = vec2(
        (uv.x - float(colIndex) * gridX) / gridX,
        (uv.y - float(rowIndex) * gridY) / gridY
    );
    
    ivec2 texCoord = ivec2(cellUV * u_resolution);
    texCoord = clamp(texCoord, ivec2(0), ivec2(u_resolution) - 1);
    vec3 col = vec3(0.0);
    
    // Fetch all ReSTIR data once for efficiency
    vec4 currentData = texelFetch(u_restir_buffer, texCoord, 0);
    vec4 currentAux = texelFetch(u_restir_aux, texCoord, 0);
    vec4 history1Data = texelFetch(u_restir_history1, texCoord, 0);
    vec4 history1Aux = texelFetch(u_restir_history1_aux, texCoord, 0);
    vec4 history2Data = texelFetch(u_restir_history2, texCoord, 0);
    vec4 history2Aux = texelFetch(u_restir_history2_aux, texCoord, 0);
    
    vec3 currentDebug = unpackReservoirAuxDebug(currentAux);
    vec3 history1Debug = unpackReservoirAuxDebug(history1Aux);
    vec3 history2Debug = unpackReservoirAuxDebug(history2Aux);
    
    if (rowIndex == 2) { // Top row
        if (colIndex == 0) {
            // Main rendered output
            col = texelFetch(u_bufferA, texCoord, 0).rgb * u_cont;
            col = pow(max(col, vec3(0.0)), gamma);
        } else if (colIndex == 1) {
            // Enhanced ReSTIR Diagnostic Display
            vec3 diagnostic = vec3(0.0);
            
            // Check all ReSTIR data sources
            float current_weight = currentData.w;
            float current_M = currentDebug.y;
            float current_age = currentDebug.x;
            float current_light = currentDebug.z;
            
            float hist1_weight = history1Data.w;
            float hist1_M = history1Debug.y;
            float hist1_age = history1Debug.x;
            
            float hist2_weight = history2Data.w;
            float hist2_M = history2Debug.y;
            float hist2_age = history2Debug.x;
            
            // Primary diagnostic: show any data at all with very sensitive thresholds
            bool has_current = (current_weight > 0.0 || current_M > 0.0 || current_age >= 0.0);
            bool has_hist1 = (hist1_weight > 0.0 || hist1_M > 0.0 || hist1_age >= 0.0);
            bool has_hist2 = (hist2_weight > 0.0 || hist2_M > 0.0 || hist2_age >= 0.0);
            
            if (has_current || has_hist1 || has_hist2) {
                // Show frame-based color coding for any activity
                diagnostic.r = clamp((current_weight * 10.0 + current_M * 0.2 + (current_age + 1.0) * 0.1), 0.0, 1.0);
                diagnostic.g = clamp((hist1_weight * 10.0 + hist1_M * 0.2 + (hist1_age + 1.0) * 0.1), 0.0, 1.0);
                diagnostic.b = clamp((hist2_weight * 10.0 + hist2_M * 0.2 + (hist2_age + 1.0) * 0.1), 0.0, 1.0);
                
                // Show light index information as overlay pattern
                if (current_light >= 0.0) {
                    float light_pattern = sin(current_light * 0.5 + float(u_frame) * 0.1) * 0.3 + 0.7;
                    diagnostic *= light_pattern;
                    
                    // Add bright white flash for active light selection
                    diagnostic = mix(diagnostic, vec3(1.0), 0.2);
                }
                
                // Enhance brightness significantly for visibility
                diagnostic = pow(diagnostic, vec3(0.5)); // Strong gamma correction
                diagnostic = clamp(diagnostic * 2.0, 0.0, 1.0); // Boost brightness
            } else {
                // DIAGNOSTIC MODE: No ReSTIR data detected - show helpful debug info
                vec2 local_uv = cellUV;
                
                // Show buffer texture verification
                vec3 buffer_test = texelFetch(u_bufferA, texCoord, 0).rgb;
                bool buffer_active = length(buffer_test) > 0.01;
                
                // Show frame counter animation
                float frame_cycle = mod(float(u_frame), 60.0) / 60.0;
                
                // Show coordinate pattern
                float coord_hash = mod(dot(gl_FragCoord.xy, vec2(1.0, 37.0)), 16.0) / 16.0;
                
                // Diagnostic color coding:
                if (buffer_active) {
                    // Scene is rendering but no ReSTIR data
                    diagnostic = vec3(
                        frame_cycle * 0.8,        // Red: animated to show frame updates
                        coord_hash * 0.3,         // Green: coordinate pattern
                        0.2                       // Blue: constant to show scene is active
                    );
                    
                    // Add pulsing to indicate "waiting for ReSTIR"
                    float pulse = sin(float(u_frame) * 0.3) * 0.2 + 0.8;
                    diagnostic *= pulse;
                } else {
                    // Scene might not be rendering at all
                    diagnostic = vec3(frame_cycle * 0.3, 0.0, coord_hash * 0.2);
                }
                
                // Error flash pattern
                if (mod(float(u_frame), 120.0) < 10.0) {
                    diagnostic = mix(diagnostic, vec3(1.0, 0.0, 0.0), 0.5); // Red flash
                }
            }
            
            col = diagnostic;
        } else if (colIndex == 1) {
            // ReSTIR Quality Assessment - shows if ReSTIR is working properly
            float current_effectiveness = calculateReSTIREffectiveness(currentData, currentAux, history1Data, history1Aux);
            
            // Show raw data for debugging when effectiveness is low
            if (current_effectiveness > 0.0) {
                // Color-code by quality
                if (current_effectiveness > 0.8) {
                    col = vec3(0.0, 1.0, 0.0); // Green = excellent ReSTIR quality
                } else if (current_effectiveness > 0.5) {
                    col = vec3(0.5, 1.0, 0.0); // Yellow-green = good quality
                } else if (current_effectiveness > 0.2) {
                    col = vec3(1.0, 0.8, 0.0); // Orange = mediocre quality
                } else {
                    col = vec3(1.0, 0.3, 0.0); // Red = poor quality
                }
                
                // Modulate by actual effectiveness value
                col *= (0.3 + current_effectiveness * 0.7);
                
                // Show convergence patterns
                float convergence_pattern = sin(float(u_frame) * 0.1 + length(uv * 20.0)) * 0.1 + 0.9;
                col *= convergence_pattern;
            } else {
                // Show raw ReSTIR data for debugging
                float weight = currentData.w;
                float M = currentDebug.y;
                
                if (weight > 0.001) {
                    // Show weight as red, M as green
                    col = vec3(clamp(weight * 10.0, 0.0, 1.0), clamp(M / 20.0, 0.0, 1.0), 0.1);
                } else {
                    // Show light color directly if available
                    col = currentAux.rgb * 2.0;
                    if (length(col) < 0.1) {
                        col = vec3(0.1, 0.0, 0.2); // Purple = no ReSTIR activity
                    }
                }
            }
            col = pow(max(col, vec3(0.0)), gamma);
        } else {
            // Temporal Reuse Verification - 2-frame comparison
            bool current_valid = isValidReservoirDebug(currentData, currentAux);
            bool hist1_valid = isValidReservoirDebug(history1Data, history1Aux);
            bool hist2_valid = isValidReservoirDebug(history2Data, history2Aux);
            
            if (current_valid) {
                float temporal_benefit = 0.0;
                int valid_history_frames = 0;
                
                // Compare with frame 1
                if (hist1_valid) {
                    float weight_ratio1 = currentData.w / max(history1Data.w, 0.001);
                    float sample_ratio1 = currentDebug.y / max(history1Debug.y, 1.0);
                    temporal_benefit += (weight_ratio1 + sample_ratio1) * 0.5;
                    valid_history_frames++;
                }
                
                // Compare with frame 2
                if (hist2_valid) {
                    float weight_ratio2 = currentData.w / max(history2Data.w, 0.001);
                    float sample_ratio2 = currentDebug.y / max(history2Debug.y, 1.0);
                    temporal_benefit += (weight_ratio2 + sample_ratio2) * 0.3; // Less weight for older frame
                    valid_history_frames++;
                }
                
                if (valid_history_frames > 0) {
                    temporal_benefit /= float(valid_history_frames);
                    temporal_benefit = clamp(temporal_benefit - 1.0, -1.0, 1.0); // Center around 0
                    
                    if (temporal_benefit > 0.1) {
                        // Green = temporal reuse is helping
                        col = mix(vec3(0.0, 0.3, 0.0), vec3(0.0, 1.0, 0.0), temporal_benefit);
                    } else if (temporal_benefit < -0.1) {
                        // Red = temporal reuse is hurting
                        col = mix(vec3(0.3, 0.0, 0.0), vec3(1.0, 0.0, 0.0), -temporal_benefit);
                    } else {
                        // Blue = stable temporal reuse
                        col = vec3(0.0, 0.2, 0.8);
                    }
                    
                    // Show frame count information
                    float frame_indicator = sin(float(valid_history_frames) * 3.14159) * 0.2 + 0.8;
                    col *= frame_indicator;
                } else {
                    col = vec3(0.5, 0.5, 0.0); // Yellow = no temporal history
                }
            } else {
                col = vec3(0.1, 0.1, 0.1); // Gray = no current sample
            }
            col = pow(max(col, vec3(0.0)), gamma);
        }
    } else if (rowIndex == 1) { // Middle row
        if (colIndex == 0) {
            // Sample Count (M) Evolution - shows temporal accumulation
            float currentM = currentDebug.y;
            float hist1M = history1Debug.y;
            float hist2M = history2Debug.y;
            
            // Show M evolution over 3 frames
            vec3 M_history = vec3(hist2M, hist1M, currentM) / 30.0; // Reduced normalization for better visibility
            M_history = clamp(M_history, 0.0, 1.0);
            
            // RGB represents the 3 frame evolution
            col = M_history;
            
            // Add brightness based on current M value
            if (currentM > 0.1) { // Lower threshold
                float intensity = clamp(currentM / 10.0, 0.3, 1.0); // More sensitive scaling
                col *= intensity;
                
                // Highlight rapid accumulation
                float accumulation_rate = (currentM - hist1M) / max(hist1M, 0.1); // Lower denominator threshold
                if (accumulation_rate > 0.2) { // Lower threshold for highlighting
                    col = mix(col, vec3(1.0, 1.0, 0.0), 0.3); // Yellow for rapid growth
                } else if (accumulation_rate < -0.2) { // Lower threshold
                    col = mix(col, vec3(1.0, 0.0, 1.0), 0.3); // Magenta for decay
                }
            } else {
                // Show any activity even if very small
                if (currentM > 0.01) {
                    col = vec3(0.2, 0.1, 0.2); // Dim purple for minimal activity
                } else {
                    col = vec3(0.05, 0.05, 0.05); // Very dark for no samples
                }
            }
            col = pow(max(col, vec3(0.0)), gamma);
        } else if (colIndex == 1) {
            // Reservoir Age and Validity Analysis - Enhanced sensitivity
            float currentAge = currentDebug.x;
            float currentWeight = currentData.w;
            float currentM = currentDebug.y;
            float hist1Age = history1Debug.x;
            float hist1Weight = history1Data.w;
            float hist1M = history1Debug.y;
            float hist2Age = history2Debug.x;
            float hist2Weight = history2Data.w;
            float hist2M = history2Debug.y;
            
            // Show any ReSTIR activity with maximum sensitivity
            vec3 age_color = vec3(0.0);
            
            // Current frame age visualization (red channel)
            if (currentWeight > 0.0001 || currentM > 0.001) { // Very low threshold
                if (currentAge > 0.0) {
                    float age_norm = clamp(currentAge / 15.0, 0.0, 1.0); // Lower max age
                    age_color.r = max(age_norm, 0.3); // Minimum brightness
                } else {
                    age_color.r = 0.5; // Fresh samples (age 0) shown as medium red
                }
            }
            
            // History frame 1 age (green channel)
            if (hist1Weight > 0.0001 || hist1M > 0.001) {
                if (hist1Age > 0.0) {
                    float age_norm = clamp(hist1Age / 15.0, 0.0, 1.0);
                    age_color.g = max(age_norm, 0.3);
                } else {
                    age_color.g = 0.5;
                }
            }
            
            // History frame 2 age (blue channel)
            if (hist2Weight > 0.0001 || hist2M > 0.001) {
                if (hist2Age > 0.0) {
                    float age_norm = clamp(hist2Age / 15.0, 0.0, 1.0);
                    age_color.b = max(age_norm, 0.3);
                } else {
                    age_color.b = 0.5;
                }
            }
            
            // Show raw data overlay when no valid age data
            if (age_color == vec3(0.0)) {
                // Direct visualization of raw values
                age_color.r = clamp(currentWeight * 20.0, 0.0, 0.4); // Weight as red
                age_color.g = clamp(currentM * 0.05, 0.0, 0.4); // M as green
                age_color.b = clamp(currentAux.r * 2.0, 0.0, 0.4); // Light contribution as blue
                
                // If still no data, show frame number pattern
                if (age_color == vec3(0.0)) {
                    float frame_indicator = mod(float(u_frame), 60.0) / 60.0;
                    age_color = vec3(0.1, 0.1, frame_indicator * 0.2); // Animated blue for debugging
                }
            }
            
            // Enhance brightness for better visibility
            age_color = pow(age_color, vec3(0.8)); // Gamma adjustment for better visibility
            col = age_color;
            col = pow(max(col, vec3(0.0)), gamma);
        } else {
            // Light Source Distribution and Diversity
            float current_light_idx = currentDebug.z;
            float hist1_light_idx = history1Debug.z;
            float hist2_light_idx = history2Debug.z;
            
            if (current_light_idx >= 0.0) {
                // Color-code by light index
                float hue = mod(current_light_idx / 8.0, 1.0);
                vec3 light_color = vec3(
                    0.5 + 0.5 * cos(hue * 6.28),
                    0.5 + 0.5 * cos(hue * 6.28 + 2.09),
                    0.5 + 0.5 * cos(hue * 6.28 + 4.19)
                );
                
                col = light_color;
                
                // Show light switching patterns (good for temporal diversity)
                bool light_switched = false;
                if (hist1_light_idx >= 0.0 && abs(current_light_idx - hist1_light_idx) > 0.5) {
                    light_switched = true;
                }
                if (hist2_light_idx >= 0.0 && abs(current_light_idx - hist2_light_idx) > 0.5) {
                    light_switched = true;
                }
                
                if (light_switched) {
                    // Pulse for light switching (indicates good sampling diversity)
                    float pulse = sin(float(u_frame) * 0.5) * 0.2 + 0.8;
                    col *= pulse;
                    col = mix(col, vec3(1.0, 1.0, 1.0), 0.2); // Brighten
                }
                
                // Modulate by light contribution strength
                vec3 light_contribution = currentAux.rgb;
                float contribution_strength = length(light_contribution);
                col *= (0.4 + clamp(contribution_strength, 0.0, 0.6));
            } else {
                col = vec3(0.1, 0.05, 0.0); // Dark brown for no light selection
            }
            col = pow(max(col, vec3(0.0)), gamma);
        }
    } else { // Bottom row (rowIndex == 0)
        if (colIndex == 0) {
            // Spatial Reuse Effectiveness Visualization
            // Sample neighboring pixels to check spatial coherence
            vec2 texel_size = 1.0 / u_resolution;
            float spatial_coherence = 0.0;
            int valid_neighbors = 0;
            
            // Check 4-neighborhood
            vec2 offsets[4] = vec2[](
                vec2(-1.0, 0.0), vec2(1.0, 0.0), vec2(0.0, -1.0), vec2(0.0, 1.0)
            );
            
            for (int i = 0; i < 4; i++) {
                ivec2 neighbor_coord = texCoord + ivec2(offsets[i]);
                if (neighbor_coord.x >= 0 && neighbor_coord.x < int(u_resolution.x) &&
                    neighbor_coord.y >= 0 && neighbor_coord.y < int(u_resolution.y)) {
                    
                    vec4 neighbor_data = texelFetch(u_restir_buffer, neighbor_coord, 0);
                    vec4 neighbor_aux = texelFetch(u_restir_aux, neighbor_coord, 0);
                    
                    if (isValidReservoirDebug(neighbor_data, neighbor_aux) && 
                        isValidReservoirDebug(currentData, currentAux)) {
                        
                        // Compare reservoir quality
                        float current_quality = currentData.w * currentDebug.y;
                        vec3 neighbor_debug = unpackReservoirAuxDebug(neighbor_aux);
                        float neighbor_quality = neighbor_data.w * neighbor_debug.y;
                        
                        float quality_ratio = current_quality / max(neighbor_quality, 0.001);
                        spatial_coherence += clamp(quality_ratio, 0.5, 2.0);
                        valid_neighbors++;
                    }
                }
            }
            
            if (valid_neighbors > 0) {
                spatial_coherence /= float(valid_neighbors);
                spatial_coherence = clamp((spatial_coherence - 1.0) * 2.0, -1.0, 1.0);
                
                if (spatial_coherence > 0.1) {
                    col = mix(vec3(0.0, 0.3, 0.0), vec3(0.0, 1.0, 0.0), spatial_coherence);
                } else if (spatial_coherence < -0.1) {
                    col = mix(vec3(0.3, 0.0, 0.0), vec3(1.0, 0.0, 0.0), -spatial_coherence);
                } else {
                    col = vec3(0.0, 0.0, 0.8); // Blue for good spatial coherence
                }
                
                // Add current sample strength
                float strength = clamp(currentData.w * 3.0, 0.2, 1.0);
                col *= strength;
            } else {
                col = vec3(0.2, 0.2, 0.2); // Gray for isolated pixels
            }
            col = pow(max(col, vec3(0.0)), gamma);
        } else if (colIndex == 1) {
            // ReSTIR vs Non-ReSTIR Comparison (simulated)
            // Show what the lighting would look like without temporal reuse
            vec3 direct_light = currentAux.rgb; // Direct light color
            float restir_weight = currentData.w;
            float restir_M = currentDebug.y;
            
            if (restir_weight > 0.001) {
                // Simulate non-ReSTIR lighting (just direct sampling)
                vec3 non_restir_estimate = direct_light * 0.3; // Reduced by typical sampling efficiency
                
                // ReSTIR enhanced lighting
                vec3 restir_estimate = direct_light * restir_weight * min(restir_M, 10.0) * 0.1;
                
                // Show the improvement
                float improvement = length(restir_estimate) / max(length(non_restir_estimate), 0.001);
                improvement = clamp(log(improvement) * 0.5 + 0.5, 0.0, 1.0);
                
                if (improvement > 0.7) {
                    col = vec3(0.0, 1.0, 0.0); // Green = significant improvement
                } else if (improvement > 0.4) {
                    col = vec3(0.5, 1.0, 0.0); // Yellow-green = moderate improvement
                } else if (improvement > 0.2) {
                    col = vec3(1.0, 0.5, 0.0); // Orange = small improvement
                } else {
                    col = vec3(1.0, 0.0, 0.0); // Red = no improvement or degradation
                }
                
                col *= (0.3 + improvement * 0.7);
                
                // Show actual light contribution as brightness
                float light_intensity = length(direct_light);
                col *= (0.5 + clamp(light_intensity, 0.0, 0.5));
            } else {
                col = vec3(0.1, 0.1, 0.1); // Dark gray for no contribution
            }
            col = pow(max(col, vec3(0.0)), gamma);
        } else {
            // Convergence and Stability Analysis
            // Show frame-to-frame stability and convergence patterns
            if (isValidReservoirDebug(currentData, currentAux)) {
                float stability_score = 0.0;
                int stability_factors = 0;
                
                // Weight stability
                if (isValidReservoirDebug(history1Data, history1Aux)) {
                    float weight_stability = 1.0 - abs(currentData.w - history1Data.w) / max(currentData.w, history1Data.w);
                    stability_score += clamp(weight_stability, 0.0, 1.0);
                    stability_factors++;
                }
                
                // Light selection stability
                if (history1Debug.z >= 0.0 && currentDebug.z >= 0.0) {
                    float light_stability = (abs(currentDebug.z - history1Debug.z) < 0.5) ? 1.0 : 0.0;
                    stability_score += light_stability;
                    stability_factors++;
                }
                
                // Sample count growth stability
                if (isValidReservoirDebug(history1Data, history1Aux)) {
                    float M_growth = (currentDebug.y - history1Debug.y) / max(history1Debug.y, 1.0);
                    float growth_stability = 1.0 - clamp(abs(M_growth), 0.0, 1.0);
                    stability_score += growth_stability;
                    stability_factors++;
                }
                
                if (stability_factors > 0) {
                    stability_score /= float(stability_factors);
                    
                    // Color code by stability
                    if (stability_score > 0.8) {
                        col = vec3(0.0, 0.0, 1.0); // Blue = very stable
                    } else if (stability_score > 0.6) {
                        col = vec3(0.0, 1.0, 1.0); // Cyan = stable
                    } else if (stability_score > 0.4) {
                        col = vec3(0.0, 1.0, 0.0); // Green = moderately stable
                    } else if (stability_score > 0.2) {
                        col = vec3(1.0, 1.0, 0.0); // Yellow = unstable
                    } else {
                        col = vec3(1.0, 0.0, 0.0); // Red = very unstable
                    }
                    
                    col *= (0.4 + stability_score * 0.6);
                    
                    // Show convergence pattern with frame counter
                    float convergence_pattern = sin(float(u_frame) * 0.05) * 0.1 + 0.9;
                    col *= convergence_pattern;
                } else {
                    col = vec3(0.3, 0.3, 0.0); // Yellow for insufficient history
                }
            } else {
                col = vec3(0.1, 0.0, 0.1); // Purple for no valid data
            }
            col = pow(max(col, vec3(0.0)), gamma);
        }
    }
    
    // Grid lines
    float lineWidth = 0.002;
    bool onVerticalGrid = (abs(uv.x - gridX) < lineWidth) || (abs(uv.x - 2.0 * gridX) < lineWidth);
    bool onHorizontalGrid = (abs(uv.y - gridY) < lineWidth) || (abs(uv.y - 2.0 * gridY) < lineWidth);
    
    if (onVerticalGrid || onHorizontalGrid) {
        col = mix(col, vec3(1.0, 1.0, 1.0), 0.7);
    }
    
    // Enhanced corner labels for 3x3 grid
    vec2 cornerDist = min(cellUV, 1.0 - cellUV);
    if (cornerDist.x < 0.02 && cornerDist.y < 0.02) {
        vec3 labelColor = vec3(1.0);
        if (rowIndex == 2) { // Top row
            if (colIndex == 0) labelColor = vec3(1.0, 0.3, 0.3);      // Main render
            else if (colIndex == 1) labelColor = vec3(0.3, 1.0, 0.3); // Quality
            else labelColor = vec3(0.3, 0.3, 1.0);                    // Temporal
        } else if (rowIndex == 1) { // Middle row
            if (colIndex == 0) labelColor = vec3(1.0, 1.0, 0.3);      // M evolution
            else if (colIndex == 1) labelColor = vec3(1.0, 0.3, 1.0); // Age/validity
            else labelColor = vec3(0.3, 1.0, 1.0);                    // Light diversity
        } else { // Bottom row
            if (colIndex == 0) labelColor = vec3(1.0, 0.6, 0.3);      // Spatial
            else if (colIndex == 1) labelColor = vec3(0.6, 1.0, 0.3); // Comparison
            else labelColor = vec3(0.6, 0.3, 1.0);                    // Convergence
        }
        col = mix(col, labelColor, 0.8);
    }
    
    FragColor = vec4(col, 1.0);
}