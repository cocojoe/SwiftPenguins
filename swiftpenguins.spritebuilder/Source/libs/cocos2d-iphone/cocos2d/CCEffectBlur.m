//
//  CCEffectBlur.m
//  cocos2d-ios
//
//  Created by Oleg Osin on 5/12/14.
//
//
//  This effect makes use of algorithms and GLSL shaders from GPUImage whose
//  license is included here.
//
//  <Begin GPUImage license>
//
//  Copyright (c) 2012, Brad Larson, Ben Cochran, Hugues Lismonde, Keitaroh
//  Kobayashi, Alaric Cole, Matthew Clark, Jacob Gundersen, Chris Williams.
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//  Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//  Neither the name of the GPUImage framework nor the names of its contributors
//  may be used to endorse or promote products derived from this software
//  without specific prior written permission.
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
//  <End GPUImage license>

#import "CCEffect_Private.h"
#import "CCEffectBlur.h"
#import "CCTexture.h"


@implementation CCEffectBlur {
    NSUInteger _numberOfOptimizedOffsets;
    NSUInteger _trueBlurRadius;
    GLfloat _sigma;
    BOOL _shaderDirty;
}

-(id)init
{
    if((self = [self initWithPixelBlurRadius:2]))
    {
        return self;
    }
    
    return self;
}


-(id)initWithPixelBlurRadius:(NSUInteger)blurRadius
{
    [self setBlurRadiusAndDependents:blurRadius];
    
    CCEffectUniform* u_blurDirection = [CCEffectUniform uniform:@"highp vec2" name:@"u_blurDirection"
                                                          value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]];

    
    unsigned long count = (unsigned long)(1 + (_numberOfOptimizedOffsets * 2));
    CCEffectVarying* v_blurCoords = [CCEffectVarying varying:@"vec2" name:@"v_blurCoordinates" count:count];
    
    if(self = [super initWithFragmentUniforms:@[u_blurDirection]
                               vertexUniforms:[NSArray arrayWithObjects:u_blurDirection, nil]
                                     varyings:[NSArray arrayWithObjects:v_blurCoords, nil]])
    {
        
        self.debugName = @"CCEffectBlur";
        self.stitchFlags = 0;
        return self;
    }
    
    return self;
}

+(id)effectWithBlurRadius:(NSUInteger)blurRadius
{
    return [[self alloc] initWithPixelBlurRadius:blurRadius];
}

-(void)setBlurRadius:(NSUInteger)blurRadius
{
    [self setBlurRadiusAndDependents:blurRadius];
    
    // The shader is constructed dynamically based on the blur radius
    // so mark it dirty and make sure this propagates up to any containing
    // effect stacks.
    _shaderDirty = YES;
    [self.owningStack passesDidChange:self];
}

- (void)setBlurRadiusAndDependents:(NSUInteger)blurRadius
{
    _trueBlurRadius = blurRadius;
    blurRadius = MIN(blurRadius, BLUR_OPTIMIZED_RADIUS_MAX);
    _blurRadius = blurRadius;
    _sigma = _trueBlurRadius / 2;
    if(_sigma == 0.0)
        _sigma = 1.0f;
    
    _numberOfOptimizedOffsets = MIN(blurRadius / 2 + (blurRadius % 2), BLUR_OPTIMIZED_RADIUS_MAX);
}

-(void)buildFragmentFunctions
{
    self.fragmentFunctions = [[NSMutableArray alloc] init];

    GLfloat *standardGaussianWeights = calloc(_trueBlurRadius + 2, sizeof(GLfloat));
    GLfloat sumOfWeights = 0.0;
    for (NSUInteger currentGaussianWeightIndex = 0; currentGaussianWeightIndex < _trueBlurRadius + 2; currentGaussianWeightIndex++)
    {
        standardGaussianWeights[currentGaussianWeightIndex] = (1.0 / sqrt(2.0 * M_PI * pow(_sigma, 2.0))) * exp(-pow(currentGaussianWeightIndex, 2.0) / (2.0 * pow(_sigma, 2.0)));
        
        if (currentGaussianWeightIndex == 0)
        {
            sumOfWeights += standardGaussianWeights[currentGaussianWeightIndex];
        }
        else
        {
            sumOfWeights += 2.0 * standardGaussianWeights[currentGaussianWeightIndex];
        }
    }
    
    // Next, normalize these weights to prevent the clipping of the Gaussian curve at the end of the discrete samples from reducing luminance
    for (NSUInteger currentGaussianWeightIndex = 0; currentGaussianWeightIndex < _trueBlurRadius + 2; currentGaussianWeightIndex++)
    {
        standardGaussianWeights[currentGaussianWeightIndex] = standardGaussianWeights[currentGaussianWeightIndex] / sumOfWeights;
    }
    
    // From these weights we calculate the offsets to read interpolated values from
    NSUInteger numberOfOptimizedOffsets = _numberOfOptimizedOffsets;
    NSUInteger trueNumberOfOptimizedOffsets = _trueBlurRadius / 2;
    
    NSMutableString *shaderString = [[NSMutableString alloc] init];
    
    // Header
    [shaderString appendFormat:@"\
     lowp vec4 sum = vec4(0.0);\n\
     vec2 compare;\
     float inBounds;\
     vec2 blurCoords;\
     "];
    
    // Inner texture loop
    [shaderString appendString:@"compare = cc_FragTexCoord1Extents - abs(v_blurCoordinates[0] - cc_FragTexCoord1Center);"];
    [shaderString appendString:@"inBounds = step(0.0, min(compare.x, compare.y));"];
    [shaderString appendFormat:@"sum += texture2D(cc_PreviousPassTexture, v_blurCoordinates[0]) * inBounds * %f;\n", (_trueBlurRadius == 0) ? 1.0 : standardGaussianWeights[0]];
    
    for (NSUInteger currentBlurCoordinateIndex = 0; currentBlurCoordinateIndex < numberOfOptimizedOffsets; currentBlurCoordinateIndex++)
    {
        GLfloat firstWeight = standardGaussianWeights[currentBlurCoordinateIndex * 2 + 1];
        GLfloat secondWeight = standardGaussianWeights[currentBlurCoordinateIndex * 2 + 2];
        GLfloat optimizedWeight = firstWeight + secondWeight;
        
        [shaderString appendFormat:@"blurCoords = v_blurCoordinates[%lu];", (unsigned long)((currentBlurCoordinateIndex * 2) + 1)];
        [shaderString appendString:@"compare = cc_FragTexCoord1Extents - abs(blurCoords - cc_FragTexCoord1Center);"];
        [shaderString appendString:@"inBounds = step(0.0, min(compare.x, compare.y));"];
        [shaderString appendFormat:@"sum += texture2D(cc_PreviousPassTexture, blurCoords) * inBounds * %f;\n", optimizedWeight];

        
        [shaderString appendFormat:@"blurCoords = v_blurCoordinates[%lu];", (unsigned long)((currentBlurCoordinateIndex * 2) + 2)];
        [shaderString appendString:@"compare = cc_FragTexCoord1Extents - abs(blurCoords - cc_FragTexCoord1Center);"];
        [shaderString appendString:@"inBounds = step(0.0, min(compare.x, compare.y));"];
        [shaderString appendFormat:@"sum += texture2D(cc_PreviousPassTexture, blurCoords) * inBounds * %f;\n", optimizedWeight];
    }
    
    // If the number of required samples exceeds the amount we can pass in via varyings, we have to do dependent texture reads in the fragment shader
    if (trueNumberOfOptimizedOffsets > numberOfOptimizedOffsets)
    {
        [shaderString appendString:@"highp vec2 singleStepOffset = u_blurDirection;\n"];
        
        for (NSUInteger currentOverlowTextureRead = numberOfOptimizedOffsets; currentOverlowTextureRead < trueNumberOfOptimizedOffsets; currentOverlowTextureRead++)
        {
            GLfloat firstWeight = standardGaussianWeights[currentOverlowTextureRead * 2 + 1];
            GLfloat secondWeight = standardGaussianWeights[currentOverlowTextureRead * 2 + 2];
            
            GLfloat optimizedWeight = firstWeight + secondWeight;
            GLfloat optimizedOffset = (firstWeight * (currentOverlowTextureRead * 2 + 1) + secondWeight * (currentOverlowTextureRead * 2 + 2)) / optimizedWeight;

            [shaderString appendFormat:@"blurCoords = v_blurCoordinates[0] + singleStepOffset * %f;", optimizedOffset];
            [shaderString appendString:@"compare = cc_FragTexCoord1Extents - abs(blurCoords - cc_FragTexCoord1Center);"];
            [shaderString appendString:@"inBounds = step(0.0, min(compare.x, compare.y));"];
            [shaderString appendFormat:@"sum += texture2D(cc_PreviousPassTexture, blurCoords) * inBounds * %f;\n", optimizedWeight];

            [shaderString appendFormat:@"blurCoords = v_blurCoordinates[0] - singleStepOffset * %f;", optimizedOffset];
            [shaderString appendString:@"compare = cc_FragTexCoord1Extents - abs(blurCoords - cc_FragTexCoord1Center);"];
            [shaderString appendString:@"inBounds = step(0.0, min(compare.x, compare.y));"];
            [shaderString appendFormat:@"sum += texture2D(cc_PreviousPassTexture, blurCoords) * inBounds * %f;\n", optimizedWeight];
        }
    }
    
    [shaderString appendString:@"\
     return sum;\n"];
    
    NSString* effectBody = [NSString stringWithString:shaderString];
    
    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"blurEffect" body:effectBody inputs:nil returnType:@"vec4"];
    [self.fragmentFunctions addObject:fragmentFunction];
    
    free(standardGaussianWeights);
}

-(void)buildVertexFunctions
{
    self.vertexFunctions = [[NSMutableArray alloc] init];
    
    GLfloat* standardGaussianWeights = calloc(_trueBlurRadius + 1, sizeof(GLfloat));
    GLfloat sumOfWeights = 0.0;
    for (NSUInteger currentGaussianWeightIndex = 0; currentGaussianWeightIndex < _trueBlurRadius + 1; currentGaussianWeightIndex++)
    {
        standardGaussianWeights[currentGaussianWeightIndex] = (1.0 / sqrt(2.0 * M_PI * pow(_sigma, 2.0))) * exp(-pow(currentGaussianWeightIndex, 2.0) / (2.0 * pow(_sigma, 2.0)));
        
        if (currentGaussianWeightIndex == 0)
        {
            sumOfWeights += standardGaussianWeights[currentGaussianWeightIndex];
        }
        else
        {
            sumOfWeights += 2.0 * standardGaussianWeights[currentGaussianWeightIndex];
        }
    }
    
    // Next, normalize these weights to prevent the clipping of the Gaussian curve at the end of the discrete samples from reducing luminance
    for (NSUInteger currentGaussianWeightIndex = 0; currentGaussianWeightIndex < _trueBlurRadius + 1; currentGaussianWeightIndex++)
    {
        standardGaussianWeights[currentGaussianWeightIndex] = standardGaussianWeights[currentGaussianWeightIndex] / sumOfWeights;
    }
    
    // From these weights we calculate the offsets to read interpolated values from
    GLfloat* optimizedGaussianOffsets = calloc(_numberOfOptimizedOffsets, sizeof(GLfloat));
    
    for (NSUInteger currentOptimizedOffset = 0; currentOptimizedOffset < _numberOfOptimizedOffsets; currentOptimizedOffset++)
    {
        GLfloat firstWeight = standardGaussianWeights[currentOptimizedOffset*2 + 1];
        GLfloat secondWeight = standardGaussianWeights[currentOptimizedOffset*2 + 2];
        
        GLfloat optimizedWeight = firstWeight + secondWeight;
        
        optimizedGaussianOffsets[currentOptimizedOffset] = (firstWeight * (currentOptimizedOffset*2 + 1) + secondWeight * (currentOptimizedOffset*2 + 2)) / optimizedWeight;
    }
    
    NSMutableString *shaderString = [[NSMutableString alloc] init];

    [shaderString appendString:@"\
     \n\
     vec2 singleStepOffset = u_blurDirection;\n"];
    
    // Inner offset loop
    [shaderString appendString:@"v_blurCoordinates[0] = cc_TexCoord1.xy;\n"];
    for (NSUInteger currentOptimizedOffset = 0; currentOptimizedOffset < _numberOfOptimizedOffsets; currentOptimizedOffset++)
    {
        [shaderString appendFormat:@"\
         v_blurCoordinates[%lu] = cc_TexCoord1.xy + singleStepOffset * %f;\n\
         v_blurCoordinates[%lu] = cc_TexCoord1.xy - singleStepOffset * %f;\n", (unsigned long)((currentOptimizedOffset * 2) + 1), optimizedGaussianOffsets[currentOptimizedOffset], (unsigned long)((currentOptimizedOffset * 2) + 2), optimizedGaussianOffsets[currentOptimizedOffset]];
    }
    
    [shaderString appendString:@"return cc_Position;\n"];

    NSString* effectBody =  [NSString stringWithString:shaderString];

    CCEffectFunction* vertexFunction = [[CCEffectFunction alloc] initWithName:@"blurEffect" body:effectBody inputs:nil returnType:@"vec4"];
    [self.vertexFunctions addObject:vertexFunction];
    
    free(optimizedGaussianOffsets);
    free(standardGaussianWeights);
}

-(void)buildRenderPasses
{
    // optmized approach based on linear sampling - http://rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/ and GPUImage - https://github.com/BradLarson/GPUImage
    // pass 0: blurs (horizontal) texture[0] and outputs blurmap to texture[1]
    // pass 1: blurs (vertical) texture[1] and outputs to texture[2]

    __weak CCEffectBlur *weakSelf = self;
    
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] initWithIndex:0];
    pass0.debugLabel = @"CCEffectBlur pass 0";
    pass0.shader = self.shader;
    pass0.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass0.beginBlocks = @[[^(CCEffectRenderPass *pass, CCTexture *previousPassTexture){

        pass.shaderUniforms[CCShaderUniformMainTexture] = previousPassTexture;
        pass.shaderUniforms[CCShaderUniformPreviousPassTexture] = previousPassTexture;
        
        pass.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:pass.texCoord1Center];
        pass.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:pass.texCoord1Extents];
        
        GLKVector2 dur = GLKVector2Make(1.0 / (previousPassTexture.pixelWidth / previousPassTexture.contentScale), 0.0);
        pass.shaderUniforms[weakSelf.uniformTranslationTable[@"u_blurDirection"]] = [NSValue valueWithGLKVector2:dur];
        
    } copy]];

    
    CCEffectRenderPass *pass1 = [[CCEffectRenderPass alloc] initWithIndex:1];
    pass1.debugLabel = @"CCEffectBlur pass 1";
    pass1.shader = self.shader;
    pass1.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass1.beginBlocks = @[[^(CCEffectRenderPass *pass, CCTexture *previousPassTexture){

        pass.shaderUniforms[CCShaderUniformPreviousPassTexture] = previousPassTexture;
        
        pass.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:GLKVector2Make(0.5f, 0.5f)];
        pass.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:GLKVector2Make(1.0f, 1.0f)];
        
        GLKVector2 dur = GLKVector2Make(0.0, 1.0 / (previousPassTexture.pixelHeight / previousPassTexture.contentScale));
        pass.shaderUniforms[weakSelf.uniformTranslationTable[@"u_blurDirection"]] = [NSValue valueWithGLKVector2:dur];
        
    } copy]];
    
    self.renderPasses = @[pass0, pass1];
}

- (CCEffectPrepareStatus)prepareForRenderingWithSprite:(CCSprite *)sprite
{
    CCEffectPrepareStatus result = CCEffectPrepareNothingToDo;
    if (_shaderDirty)
    {
        unsigned long count = (unsigned long)(1 + (_numberOfOptimizedOffsets * 2));
        CCEffectVarying* v_blurCoords = [CCEffectVarying varying:@"vec2" name:@"v_blurCoordinates" count:count];
        [self setVaryings:@[v_blurCoords]];

        [self buildFragmentFunctions];
        [self buildVertexFunctions];
        [self buildEffectShader];
        [self buildRenderPasses];
        
        _shaderDirty = NO;
        result = CCEffectPrepareSuccess;
    }
    return result;
}

@end

