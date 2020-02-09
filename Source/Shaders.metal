// Point and Line orbit traps: http://www.iquilezles.org/www/articles/ftrapsgeometric/ftrapsgeometric.htm
// foam style: https://fractalforums.org/programming/11/mandelbrot-foam/2360
// variations: https://fractalforums.org/share-a-fractal/22/a-few-mandelbrot-variations-i-discovered-stay-tuned-for-more/216
// Lyapunov : https://www.shadertoy.com/view/Mds3R8
// 'retry' idea: http://www.fractalforums.com/index.php?action=gallery;sa=view;id=20565

#include <metal_stdlib>
#import "Shader.h"

using namespace metal;

float2 complexPower(float2 value, float power) {
    float rr = value.x * value.x + value.y * value.y; // radius squared
    if(rr == 0) return 0.0001;
    
    float p1 = pow(rr, power / 2);
    float arg = atan2(value.y, value.x);
    float2 p2 = float2( cos(power * arg), sin(power * arg));
    return p1 * p2;
}

float2 complexConjugate(float2 v) { return float2(v.x,-v.y); }
float2 complexAdd(float2 v1, float2 v2) { return float2(v1.x + v2.x, v1.y + v2.y); }
float2 complexMul(float2 v1, float2 v2) { return float2(v1.x * v2.x - v1.y * v2.y, v1.x * v2.y + v1.y * v2.x); }
float2 csqr(float2 z) { return float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y); }

float2 complexDiv(float2 v1, float2 v2) {
    float rr = v2.x * v2.x + v2.y * v2.y; // radius squared
    float2 con = complexConjugate(v2);
    
    float2 cn = float2(con.x / rr, con.y / rr);
    return complexMul(v1, cn);
}

kernel void fractalShader
(
 texture2d<float, access::write> outTexture [[texture(0)]],
 device TVertex* vData      [[ buffer(0) ]],
 constant Control &control  [[ buffer(1) ]],
 constant float3 *color     [[ buffer(2) ]],    // color lookup table[256]
 uint2 srcP [[thread_position_in_grid]])
{
    uint2 p = srcP; // copy of pixel coordinate, altered during radial symmetry
    float2 c;
    
    // apply radial symmetry? ---------
    if(control.radialAngle > 0.01) { // 0 = don't apply
        float centerX = control.xSize/2;
        float centerY = control.ySize/2;
        float dx = float(srcP.x - centerX);
        float dy = float(srcP.y - centerY);

        float angle = fabs(atan2(dy,dx));

        float dRatio = 0.01 + control.radialAngle;
        while(angle > dRatio) angle -= dRatio;
        if(angle > dRatio/2) angle = dRatio - angle;

        float dist = sqrt(dx * dx + dy * dy);

        p.x = uint(centerX + cos(angle) * dist);
        p.y = uint(centerY + sin(angle) * dist);
    }
    
    if(control.is3DWindow == 0) {        // 2D fractal in Main window
        if(srcP.x >= uint(control.xSize)) return; // screen size not evenly divisible by threadGroups
        if(srcP.y >= uint(control.ySize)) return;
        c = float2(control.xmin + control.dx * float(p.x), control.ymin + control.dy * float(p.y));
        
        if(control.win3DFlag > 0) {  // draw 3D bounding box
            bool mark = false;
            if(c.x >= control.xmin3D && c.x <= control.xmax3D) {
                if(c.y >= control.ymin3D && c.y <= control.ymin3D + control.dy) mark = true; else
                    if(c.y >= control.ymax3D && c.y <= control.ymax3D + control.dy) mark = true;
            }
            if(!mark) {
                if(c.y >= control.ymin3D && c.y <= control.ymax3D) {
                    if(c.x >= control.xmin3D && c.x <= control.xmin3D + control.dx) mark = true; else
                        if(c.x >= control.xmax3D && c.x <= control.xmax3D + control.dx) mark = true;
                }
            }
            
            if(mark) {
                outTexture.write(float4(1,1,1,1),p);
                return;
            }
        }
    }
    else {  // 3D rendition in second window
        if(srcP.x >= uint(SIZE3D)) return; // screen size not evenly divisible by threadGroups
        if(srcP.y >= uint(SIZE3D)) return;
        c = float2(control.xmin3D + control.dx3D * float(p.x), control.ymin3D + control.dy3D * float(p.y));
    }
    
    int iter;
    int maxIter = int(control.maxIter) * (control.retry + 1);
    int skip = int(control.skip);
    float avg = 0;
    float lastAdded = 0;
    float count = 0;
    float2 z = float2();
    float zr,z2 = 0;
    float minDist = 999;
    float2 q,w;
    float x,h = 0.5;
    int retry = 0;
    
    float br = c.x;
    float bi = c.y;
    float ar=0;
    float ai = control.power / 10; // 0.58;
    float aar=ar*ar;
    float aai=ai*ai;
    
    if(control.variation == 1 || control.variation > 2) {
        z = float2(1/control.power,0);
        q = float2(control.foamQ, 0);
        w = float2(control.foamW, 0);
    }
    
    for(iter = 0;iter < maxIter;++iter) {
        switch(control.variation) {
            case 0 :    // original Mandelbrot
                z = complexPower(z,control.power) + c;
                break;
                
            case 1 :    // Foam
                w = complexDiv( complexMul(q,w),z);
                z = complexAdd( complexAdd( csqr(z), csqr(w)),c);
                break;
                
            case 2 :    // chicken
                z = complexPower(z,control.power) + c;
                if(z.y < 0) z.y = -z.y;
                break;
                
            case 3 :    // variation #3
                ai=2.0*ar*ai+bi;
                ar=aar-aai+br;
                aar=ar*ar;
                aai=ai*ai;
                
                z.x = ar;
                z.y = ai;
                //                zr = z.x;
                //                if (z.x > 0) {
                //                    z.x = z.x*z.x - z.y*z.y + c.x;
                //                    z.y = 2*zr*abs(z.y) + c.y;
                //                } else {
                //                    z.x = z.x*z.x - z.y*z.y + c.x;
                //                    z.y = 2*abs(zr)*z.y + c.y;
                //                }
                break;
                
            case 4 : // variation #8
                zr = z.x;
                if (z.y > 0) {
                    z.x = abs(z.x*z.x - z.y*z.y) + c.x;
                    z.y = 2*zr*z.y + c.y;
                } else {
                    z.x = (z.x*z.x - z.y*z.y) + c.x;
                    z.y = 2*zr*z.y + abs(c.y);
                }
                break;
                
            case 5 : // variation # 9
                zr = z.x;
                z.x = (z.x*z.x - z.y*z.y) + c.x;
                z.y = -2*abs(zr)*z.y + c.y;
                zr = z.x;
                z.x = (z.x*z.x - z.y*z.y);
                z.y = 2*abs(zr)*z.y + c.y;
                break;
                
            case 6 : // variation #12
                zr = z.x;
                z.x = -(z.x*z.x - 3*z.y*z.y)*(z.x) + c.x;
                z.y = -abs(3*zr*zr - z.y*z.y)*(z.y) + c.y;
                break;
                
            case LYAPUNOV :
                float base = control.power * 3;
                x = c.x*x*(base-x); h += log2(abs(c.x*(base-2.0*x)));
                x = c.x*x*(base-x); h += log2(abs(c.x*(base-2.0*x)));
                x = c.x*x*(base-x); h += log2(abs(c.x*(base-2.0*x)));
                x = c.x*x*(base-x); h += log2(abs(c.x*(base-2.0*x)));
                x = c.x*x*(base-x); h += log2(abs(c.x*(base-2.0*x)));
                x = c.x*x*(base-x); h += log2(abs(c.x*(base-2.0*x)));
                
                float stretch = 6;
                x = stretch * c.y*x*(base-x); h += log2(abs(c.y*(base-2.0*x)));
                x = stretch * c.y*x*(base-x); h += log2(abs(c.y*(base-2.0*x)));
                x = stretch * c.y*x*(base-x); h += log2(abs(c.y*(base-2.0*x)));
                x = stretch * c.y*x*(base-x); h += log2(abs(c.y*(base-2.0*x)));
                x = stretch * c.y*x*(base-x); h += log2(abs(c.y*(base-2.0*x)));
                x = stretch * c.y*x*(base-x); h += log2(abs(c.y*(base-2.0*x)));
                
                h = sqrt(abs(h));
                z.y = sin(control.escapeRadius * h * 0.1);
                z.x = 0.5 + 5 * sin(2.5 * h);
                break;
        }
        
        if(control.coloringFlag && (iter >= skip)) {
            count += 1;
            lastAdded = 0.5 + 0.5 * sin(control.stripeDensity * atan2(z.y, z.x));
            avg += lastAdded;
        }
        
        // point,line orbit traps ------------------------------------------
        for(int i=0;i<3;++i) {
            if(control.pTrap[i].active) {
                float dist = length(z - float2(control.pTrap[i].x,control.pTrap[i].y));
                minDist = min(minDist, dist * dist);
            }
            if(control.lTrap[i].active) {
                float A = z.x - control.lTrap[i].x;
                float B = z.y - control.lTrap[i].y;
                float C = 1;  // x2 - x1
                float D = control.lTrap[i].slope; // y2 - y1
                float dist = abs(A * D - C * B) / sqrt(C * C + D * D);
                
                minDist = min(minDist, dist * dist);
            }
        }
        // -----------------------------------------------------------------
        
        if(control.variation == 3) {
            if(aar+aai > 5) {
                z2 = dot(z,z);
                break;
            }
        }
        else {
            z2 = dot(z,z);
            if (z2 > control.escapeRadius && iter > skip) {
                if(retry < control.retry) {
                    ++retry;
                    z2 *= 0.01;
                }
                else break;
            }
        }
    }
    
    float3 icolor = float3();
    
    if(control.coloringFlag) {
        if(count > 1) {
            float fracDen = (minDist > 900) ? log(z2) : minDist * minDist;
            float prevAvg = (avg - lastAdded) / (count - 1.0);
            avg = avg / count;
            
            float frac = 1.0 + (log2(log(control.escapeRadius) / fracDen));
            float mix = frac * avg + (1.0 - frac) * prevAvg;
            
            if(iter < maxIter) {
                float co = mix * pow(10.0,control.multiplier) * 6.2831;
                icolor.x = 0.5 + 0.5 * cos(co + control.R);
                icolor.y = 0.5 + 0.5 * cos(co + control.G);
                icolor.z = 0.5 + 0.5 * cos(co + control.B);
            }
        }
    }
    else {
        iter = (minDist > 900) ? iter * 2 : int(minDist * minDist);
        if(control.variation == 1) iter = (iter - 10) * 3; // Foam
        
        if(iter < 0) iter = 0; else if(iter > 255) iter = 255;
        
        icolor = color[iter];
    }
    
    icolor.x = 0.5 + (icolor.x - 0.5) * control.contrast;
    icolor.y = 0.5 + (icolor.y - 0.5) * control.contrast;
    icolor.z = 0.5 + (icolor.z - 0.5) * control.contrast;
    
    if(control.is3DWindow == 0) {        // 2D fractal in Main window
        outTexture.write(float4(icolor,1),srcP);
    }
    else { // 3D rendition in second window
        if(icolor.x < 0.1 && icolor.y < 0.1 && icolor.z < 0.1) icolor = float3(0.3);
        
        int index = int(SIZE3D - 1 - p.y) * SIZE3D + int(p.x);
        vData[index].color = float4(icolor,1);
        vData[index].height = float(iter);
    }
}

// ======================================================================

kernel void shadowShader
(
 texture2d<float, access::read> src [[texture(0)]],
 texture2d<float, access::write> dst [[texture(1)]],
 constant Control &control [[buffer(0)]],
 uint2 p [[thread_position_in_grid]])
{
    if(p.x > uint(control.xSize)) return; // screen size not evenly divisible by threadGroups
    if(p.y > uint(control.ySize)) return;
    
    float4 v = src.read(p);
    
    if(p.x > 1 && p.y > 1) {
        bool shadow = false;
        
        {
            uint2 p2 = p;
            p2.x -= 1;
            float4 vx = src.read(p2);
            if(v.x < vx.x || v.y < vx.y) shadow = true;
        }
        
        if(!shadow)
        {
            uint2 p2 = p;
            p2.y -= 1;
            float4 vx = src.read(p2);
            if(v.x < vx.x || v.y < vx.y) shadow = true;
        }
        
        if(!shadow)
        {
            uint2 p2 = p;
            p2.x -= 1;
            p2.y -= 1;
            float4 vx = src.read(p2);
            if(v.x < vx.x || v.y < vx.y) shadow = true;
        }
        
        if(shadow) {
            v.x /= 4;
            v.y /= 4;
            v.z /= 4;
        }
    }
    
    dst.write(v,p);
}

/////////////////////////////////////////////////////////////////////////

struct Transfer {
    float4 position [[position]];
    float4 lighting;
    float4 color;
};

vertex Transfer texturedVertexShader
(
 constant TVertex *data[[ buffer(0) ]],
 constant Uniforms &uniforms[[ buffer(1) ]],
 unsigned int vid [[ vertex_id ]])
{
    TVertex in = data[vid];
    Transfer out;
    
    out.color = in.color;
    out.position = uniforms.mvp * float4(in.position, 1.0);
    
    float distance = length(uniforms.light.position - in.position.xyz);
    float intensity = uniforms.light.ambient + saturate(dot(in.normal.rgb, uniforms.light.position) / pow(distance,uniforms.light.power) );
    out.lighting = float4(intensity,intensity,intensity,1);
    
    return out;
}

fragment float4 texturedFragmentShader
(
 Transfer data [[stage_in]])
{
    return data.color * data.lighting;
}

/////////////////////////////////////////////////////////////////////////

kernel void normalShader
(
 device TVertex* v [[ buffer(0) ]],
 uint2 p [[thread_position_in_grid]])
{
    if(p.x >= SIZE3D || p.y >= SIZE3D) return; // data size not evenly divisible by threadGroups
    
    int i = int(p.y) * SIZE3D + int(p.x);
    int i2 = i + ((p.x < SIZE3Dm) ? 1 : -1);
    int i3 = i + ((p.y < SIZE3Dm) ? SIZE3D : -SIZE3D);
    
    TVertex v1 = v[i];
    TVertex v2 = v[i2];
    TVertex v3 = v[i3];
    
    v[i].normal = normalize(cross(v1.position - v2.position, v1.position - v3.position));
}

/////////////////////////////////////////////////////////////////////////

kernel void smoothingShader
(
 constant TVertex* src      [[ buffer(0) ]],
 device TVertex* dst        [[ buffer(1) ]],
 constant Control &control  [[ buffer(2) ]],
 uint2 p [[thread_position_in_grid]])
{
    int2 pp = int2(p);
    
    if(pp.x >= SIZE3D || pp.y >= SIZE3D) return; // data size not evenly divisible by threadGroups
    
    int index = pp.y * SIZE3D + pp.x;
    
    // determine average height of eight neighbors
    int count = 0;
    float totalHeight = 0;
    
    for(int x = -1; x <= 1; ++x) {
        if(pp.x + x < 0) continue;
        if(pp.x + x > SIZE3Dm) continue;
        
        for(int y = -1; y <= 1; ++y) {
            if(pp.y + y < 0) continue;
            if(pp.y + y > SIZE3Dm) continue;
            
            int index2 = index + y * SIZE3D + x;
            totalHeight += src[index2].height;
            
            ++count;
        }
    }
    
    float averageHt = totalHeight / float(count);
    
    // smoothed height
    float ht = src[index].height * control.smooth  + averageHt * (1 - control.smooth);
    
    TVertex v = src[index];
    v.position.y = (ht) * control.height / 3.0;
    
    dst[index] = v;
}

