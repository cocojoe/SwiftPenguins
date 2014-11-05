//
//  CCEffectLighting.m
//  cocos2d-ios
//
//  Created by Thayer J Andrews on 10/2/14.
//
//

#import "CCEffectLighting.h"

#if CC_EFFECTS_EXPERIMENTAL

#import "CCDirector.h"
#import "CCEffectUtils.h"
#import "CCRenderer.h"
#import "CCSpriteFrame.h"
#import "CCTexture.h"

#import "CCEffect_Private.h"
#import "CCSprite_Private.h"

typedef struct _CCLightKey
{
    NSUInteger pointLightMask;
    NSUInteger directionalLightMask;

} CCLightKey;

static CCLightKey CCLightKeyMake(NSArray *lights);
static BOOL CCLightKeyCompare(CCLightKey a, CCLightKey b);



@interface CCEffectLighting ()

@property (nonatomic, strong) NSMutableArray *lights;
@property (nonatomic, assign) CCLightKey lightKey;
@property (nonatomic, readonly) BOOL needsSpecular;
@property (nonatomic, assign) BOOL shaderHasSpecular;
@property (nonatomic, assign) BOOL shaderHasNormalMap;

@end


@implementation CCEffectLighting

-(id)init
{
    return [self initWithLights:nil];
}

-(id)initWithLights:(NSArray *)lights
{
    if((self = [super init]))
    {
        self.debugName = @"CCEffectLighting";
        
        if (lights)
        {
            _lights = [lights mutableCopy];
        }
        else
        {
            _lights = [[NSMutableArray alloc] init];
        }
        
        _specularColor = [CCColor whiteColor];
        _shininess = 5.0f;
        
        _lightKey = CCLightKeyMake(lights);
        _shaderHasSpecular = NO;
        _shaderHasNormalMap = NO;
    }
    return self;
}

+(id)effectWithLights:(NSArray *)lights
{
    return [[self alloc] initWithLights:lights];
}

-(void)addLight:(CCLightNode *)light
{
    NSAssert(_lights.count < 16, @"CCEffectLighting only supports 16 lights.");
    NSAssert(![_lights containsObject:light], @"Adding a light to effect that is already here.");
    [_lights addObject:light];
}

-(void)removeLight:(CCLightNode *)light
{
    NSAssert([_lights containsObject:light], @"Removing a light from effect that is not here.");
    [_lights removeObject:light];
}

-(void)removeAllLights
{
    [_lights removeAllObjects];
}


+(NSMutableArray *)buildFragmentFunctionsWithLights:(NSArray*)lights normalMap:(BOOL)needsNormalMap specular:(BOOL)needsSpecular
{
    CCEffectFunctionInput *input = [[CCEffectFunctionInput alloc] initWithType:@"vec4" name:@"inputValue" initialSnippet:CCEffectDefaultInitialInputSnippet snippet:CCEffectDefaultInputSnippet];
    
    NSMutableString *effectBody = [[NSMutableString alloc] init];
    [effectBody appendString:CC_GLSL(
                                     vec4 lightColor;
                                     vec4 lightSpecularColor;
                                     vec4 diffuseSum = u_globalAmbientColor;
                                     vec4 specularSum = vec4(0,0,0,0);
                                     
                                     vec3 tangentSpaceLightDir;
                                     vec3 halfAngleDir;
                                     
                                     float lightDist;
                                     float falloffTerm;
                                     float diffuseTerm;
                                     float specularTerm;
                                     float composedAlpha = inputValue.a;
                                     )];

    if (needsNormalMap)
    {
        [effectBody appendString:CC_GLSL(
                                         // Index the normal map and expand the color value from [0..1] to [-1..1]
                                         vec4 normalMap = texture2D(cc_NormalMapTexture, cc_FragTexCoord2);
                                         vec3 tangentSpaceNormal = normalize(normalMap.xyz * 2.0 - 1.0);
                                         composedAlpha *= normalMap.a;
                                         )];
    }
    else
    {
        [effectBody appendString:@"vec3 tangentSpaceNormal = vec3(0,0,1);\n"];
    }
    
    [effectBody appendString:CC_GLSL(
                                     if (composedAlpha == 0.0)
                                     {
                                         return vec4(0,0,0,0);
                                     }
                                     )];
    
    for (NSUInteger lightIndex = 0; lightIndex < lights.count; lightIndex++)
    {
        CCLightNode *light = lights[lightIndex];
        if (light.type == CCLightDirectional)
        {
            [effectBody appendFormat:@"tangentSpaceLightDir = v_tangentSpaceLightDir%lu.xyz;\n", (unsigned long)lightIndex];
            [effectBody appendFormat:@"lightColor = u_lightColor%lu;\n", (unsigned long)lightIndex];
            [effectBody appendFormat:@"lightSpecularColor = u_lightSpecularColor%lu;\n", (unsigned long)lightIndex];
        }
        else
        {
            [effectBody appendFormat:@"tangentSpaceLightDir = normalize(v_tangentSpaceLightDir%lu.xyz);\n", (unsigned long)lightIndex];
            [effectBody appendFormat:@"lightDist = length(v_tangentSpaceLightDir%lu.xyz);\n", (unsigned long)lightIndex];
            [effectBody appendFormat:@"falloffTerm = max(0.0, (1.0 - lightDist * u_lightFalloff%lu));\n", (unsigned long)lightIndex];
            [effectBody appendFormat:@"lightColor = u_lightColor%lu * falloffTerm;\n", (unsigned long)lightIndex];
            if (needsSpecular)
            {
                [effectBody appendFormat:@"lightSpecularColor = u_lightSpecularColor%lu * falloffTerm;\n", (unsigned long)lightIndex];
            }
        }
        [effectBody appendString:@"diffuseTerm = max(0.0, dot(tangentSpaceNormal, tangentSpaceLightDir));\n"];
        [effectBody appendString:@"diffuseSum += lightColor * diffuseTerm;\n"];
        
        if (needsSpecular)
        {
            [effectBody appendString:@"halfAngleDir = (2.0 * dot(tangentSpaceLightDir, tangentSpaceNormal) * tangentSpaceNormal - tangentSpaceLightDir);\n"];
            [effectBody appendString:@"specularTerm = max(0.0, dot(halfAngleDir, vec3(0,0,1))) * step(0.0, diffuseTerm);\n"];
            [effectBody appendString:@"specularSum += lightSpecularColor * pow(specularTerm, u_specularExponent);\n"];
        }
    }
    [effectBody appendString:@"vec4 resultColor = diffuseSum * inputValue;\n"];
    if (needsSpecular)
    {
        [effectBody appendString:@"resultColor += specularSum * u_specularColor;\n"];
    }
    [effectBody appendString:@"return vec4(resultColor.xyz, inputValue.a);\n"];
    
    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"lightingEffectFrag" body:effectBody inputs:@[input] returnType:@"vec4"];
    return [NSMutableArray arrayWithObject:fragmentFunction];
}

+(NSMutableArray *)buildVertexFunctionsWithLights:(NSArray*)lights
{
    NSMutableString *effectBody = [[NSMutableString alloc] init];
    for (NSUInteger lightIndex = 0; lightIndex < lights.count; lightIndex++)
    {
        CCLightNode *light = lights[lightIndex];
        
        if (light.type == CCLightDirectional)
        {
            [effectBody appendFormat:@"v_tangentSpaceLightDir%lu = u_lightVector%lu;", (unsigned long)lightIndex, (unsigned long)lightIndex];
        }
        else
        {
            [effectBody appendFormat:@"v_tangentSpaceLightDir%lu = u_lightVector%lu - u_ndcToTangentSpace * cc_Position;", (unsigned long)lightIndex, (unsigned long)lightIndex];
        }
    }
    [effectBody appendString:@"return cc_Position;"];
    
    CCEffectFunction *vertexFunction = [[CCEffectFunction alloc] initWithName:@"lightingEffectVtx" body:effectBody inputs:nil returnType:@"vec4"];
    return [NSMutableArray arrayWithObject:vertexFunction];
}

-(void)buildRenderPasses
{
    __weak CCEffectLighting *weakSelf = self;
    
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectLighting pass 0";
    pass0.shader = self.shader;
    pass0.beginBlocks = @[[^(CCEffectRenderPass *pass, CCTexture *previousPassTexture){
        
        pass.shaderUniforms[CCShaderUniformMainTexture] = previousPassTexture;
        pass.shaderUniforms[CCShaderUniformPreviousPassTexture] = previousPassTexture;
        pass.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:pass.texCoord1Center];
        pass.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:pass.texCoord1Extents];

        // Matrix for converting NDC (normalized device coordinates (aka normalized render target coordinates)
        // to node local coordinates.
        pass.shaderUniforms[weakSelf.uniformTranslationTable[@"u_ndcToTangentSpace"]] = [NSValue valueWithGLKMatrix4:pass.ndcToNodeLocal];

        GLKVector4 globalAmbientColor = GLKVector4Make(0.0f, 0.0f, 0.0f, 1.0f);
        for (NSUInteger lightIndex = 0; lightIndex < weakSelf.lights.count; lightIndex++)
        {
            CCLightNode *light = weakSelf.lights[lightIndex];
            
            // Add this light's ambient contribution to the global ambient light color.
            globalAmbientColor = GLKVector4Add(globalAmbientColor, GLKVector4MultiplyScalar(light.ambientColor.glkVector4, light.ambientIntensity));

            // Get the transform from the light's coordinate space to the effect's coordinate space.
            GLKMatrix4 lightNodeToEffectNode = CCEffectUtilsTransformFromNodeToNode(light, pass.node, nil);
            
            // Compute the light's position in the effect node's coordinate system.
            GLKVector4 lightVector = GLKVector4Make(0.0f, 0.0f, 0.0f, 0.0f);
            if (light.type == CCLightDirectional)
            {
                lightVector = GLKVector4Normalize(GLKMatrix4MultiplyVector4(lightNodeToEffectNode, GLKVector4Make(0.0f, 1.0f, light.depth, 0.0f)));
            }
            else
            {
                lightVector = GLKMatrix4MultiplyVector4(lightNodeToEffectNode, GLKVector4Make(light.anchorPointInPoints.x, light.anchorPointInPoints.y, light.depth, 1.0f));

                float falloff = (light.cutoffRadius > 0.0f) ? 1.0f / light.cutoffRadius : 0.0f;
                NSString *lightFalloffLabel = [NSString stringWithFormat:@"u_lightFalloff%lu", (unsigned long)lightIndex];
                pass.shaderUniforms[weakSelf.uniformTranslationTable[lightFalloffLabel]] = [NSNumber numberWithFloat:falloff];
            }
            
            // Compute the real light color based on color and intensity.
            GLKVector4 lightColor = GLKVector4MultiplyScalar(light.color.glkVector4, light.intensity);
            
            NSString *lightColorLabel = [NSString stringWithFormat:@"u_lightColor%lu", (unsigned long)lightIndex];
            pass.shaderUniforms[weakSelf.uniformTranslationTable[lightColorLabel]] = [NSValue valueWithGLKVector4:lightColor];

            NSString *lightVectorLabel = [NSString stringWithFormat:@"u_lightVector%lu", (unsigned long)lightIndex];
            pass.shaderUniforms[weakSelf.uniformTranslationTable[lightVectorLabel]] = [NSValue valueWithGLKVector4:lightVector];

            if (self.needsSpecular)
            {
                GLKVector4 lightSpecularColor = GLKVector4MultiplyScalar(light.specularColor.glkVector4, light.specularIntensity);

                NSString *lightSpecularColorLabel = [NSString stringWithFormat:@"u_lightSpecularColor%lu", (unsigned long)lightIndex];
                pass.shaderUniforms[weakSelf.uniformTranslationTable[lightSpecularColorLabel]] = [NSValue valueWithGLKVector4:lightSpecularColor];
            }
        }

        pass.shaderUniforms[weakSelf.uniformTranslationTable[@"u_globalAmbientColor"]] = [NSValue valueWithGLKVector4:globalAmbientColor];
        
        if (self.needsSpecular)
        {
            pass.shaderUniforms[weakSelf.uniformTranslationTable[@"u_specularExponent"]] = [NSNumber numberWithFloat:weakSelf.shininess];
            pass.shaderUniforms[weakSelf.uniformTranslationTable[@"u_specularColor"]] = [NSValue valueWithGLKVector4:weakSelf.specularColor.glkVector4];
        }
        
    } copy]];
    
    self.renderPasses = @[pass0];
}

- (CCEffectPrepareStatus)prepareForRenderingWithSprite:(CCSprite *)sprite
{
    CCEffectPrepareStatus result = CCEffectPrepareNothingToDo;

    BOOL needsNormalMap = (sprite.normalMapSpriteFrame != nil);
    
    CCLightKey newLightKey = CCLightKeyMake(_lights);
    if (!self.shader ||
        !CCLightKeyCompare(newLightKey, _lightKey) ||
        (_shaderHasSpecular != self.needsSpecular) ||
        (_shaderHasNormalMap != needsNormalMap))
    {
        _lightKey = newLightKey;
        _shaderHasSpecular = self.needsSpecular;
        _shaderHasNormalMap = needsNormalMap;
        
        NSMutableArray *fragUniforms = [[NSMutableArray alloc] initWithArray:@[[CCEffectUniform uniform:@"vec4" name:@"u_globalAmbientColor" value:[NSValue valueWithGLKVector4:GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f)]]]];
        NSMutableArray *vertUniforms = [[NSMutableArray alloc] initWithArray:@[[CCEffectUniform uniform:@"mat4" name:@"u_ndcToTangentSpace" value:[NSValue valueWithGLKMatrix4:GLKMatrix4Identity]]]];
        NSMutableArray *varyings = [[NSMutableArray alloc] init];
        
        for (NSUInteger lightIndex = 0; lightIndex < _lights.count; lightIndex++)
        {
            CCLightNode *light = _lights[lightIndex];
            
            [vertUniforms addObject:[CCEffectUniform uniform:@"vec4" name:[NSString stringWithFormat:@"u_lightVector%lu", (unsigned long)lightIndex] value:[NSValue valueWithGLKVector4:GLKVector4Make(0.0f, 0.0f, 0.0f, 1.0f)]]];
            [fragUniforms addObject:[CCEffectUniform uniform:@"vec4" name:[NSString stringWithFormat:@"u_lightColor%lu", (unsigned long)lightIndex] value:[NSValue valueWithGLKVector4:GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f)]]];
            if (self.needsSpecular)
            {
                [fragUniforms addObject:[CCEffectUniform uniform:@"vec4" name:[NSString stringWithFormat:@"u_lightSpecularColor%lu", (unsigned long)lightIndex] value:[NSValue valueWithGLKVector4:GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f)]]];
            }
            
            if (light.type != CCLightDirectional)
            {
                [fragUniforms addObject:[CCEffectUniform uniform:@"float" name:[NSString stringWithFormat:@"u_lightFalloff%lu", (unsigned long)lightIndex] value:[NSNumber numberWithFloat:1.0f]]];
            }
            
            [varyings addObject:[CCEffectVarying varying:@"vec4" name:[NSString stringWithFormat:@"v_tangentSpaceLightDir%lu", (unsigned long)lightIndex]]];
        }
        
        if (self.needsSpecular)
        {
            [fragUniforms addObject:[CCEffectUniform uniform:@"float" name:@"u_specularExponent" value:[NSNumber numberWithFloat:5.0f]]];
            [fragUniforms addObject:[CCEffectUniform uniform:@"vec4" name:@"u_specularColor" value:[NSValue valueWithGLKVector4:GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f)]]];
        }
        
        NSMutableArray *fragFunctions = [CCEffectLighting buildFragmentFunctionsWithLights:_lights normalMap:needsNormalMap specular:self.needsSpecular];
        NSMutableArray *vertFunctions = [CCEffectLighting buildVertexFunctionsWithLights:_lights];
        
        [self buildEffectWithFragmentFunction:fragFunctions vertexFunctions:vertFunctions fragmentUniforms:fragUniforms vertexUniforms:vertUniforms varyings:varyings firstInStack:YES];

        result = CCEffectPrepareSuccess;
    }
    return result;
}

- (BOOL)needsSpecular
{
    return (!ccc4FEqual(_specularColor.ccColor4f, ccc4f(0.0f, 0.0f, 0.0f, 0.0f)) && (_shininess > 0.0f));
}

@end

CCLightKey CCLightKeyMake(NSArray *lights)
{
    CCLightKey lightKey;
    lightKey.pointLightMask = 0;
    lightKey.directionalLightMask = 0;
    
    for (NSUInteger lightIndex = 0; lightIndex < lights.count; lightIndex++)
    {
        CCLightNode *light = lights[lightIndex];
        if (light.type == CCLightPoint)
        {
            lightKey.pointLightMask |= (1 << lightIndex);
        }
        else if (light.type == CCLightDirectional)
        {
            lightKey.directionalLightMask |= (1 << lightIndex);
        }
    }
    return lightKey;
}

BOOL CCLightKeyCompare(CCLightKey a, CCLightKey b)
{
    return (((a.pointLightMask) == (b.pointLightMask)) &&
            ((a.directionalLightMask) == (b.directionalLightMask)));
}

#endif
