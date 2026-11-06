#!/usr/bin/env python3
"""Generate a plain Xcode project without requiring XcodeGen or CocoaPods."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent
project = root / 'LaneAhead.xcodeproj'
project.mkdir(exist_ok=True)
objects = {}

def ident(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24].upper()

def raw(value):
    if isinstance(value, dict): return '{ ' + ' '.join(f'{raw(str(k))} = {raw(v)};' for k, v in value.items()) + ' }'
    if isinstance(value, list): return '( ' + ', '.join(raw(v) for v in value) + ' )'
    if isinstance(value, int): return str(value)
    return json.dumps(str(value), ensure_ascii=False)

def obj(label, **values):
    key = ident(label)
    objects[key] = values
    return key

def file(path, kind):
    return obj('file:' + path, isa='PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='SOURCE_ROOT')

sources, resources, groups = [], [], {}
for path in sorted((root / 'LaneAhead').rglob('*')):
    if not path.is_file(): continue
    relative = str(path.relative_to(root))
    suffix = path.suffix
    if suffix in ['.swift', '.m', '.h']:
        group = path.relative_to(root / 'LaneAhead').parts[0]
        ref = file(relative, {'.swift':'sourcecode.swift','.m':'sourcecode.c.objc','.h':'sourcecode.c.h'}[suffix])
        groups.setdefault(group, []).append(ref)
        if suffix != '.h': sources.append(obj('build:'+relative, isa='PBXBuildFile', fileRef=ref))
    elif path.parent == root / 'LaneAhead/Resources':
        ref = file(relative, 'text.plist.xml' if suffix in ['.plist','.xcprivacy'] else 'image.png')
        groups.setdefault('Resources', []).append(ref)
        resources.append(obj('build:'+relative, isa='PBXBuildFile', fileRef=ref))

assets = file('LaneAhead/Assets.xcassets', 'folder.assetcatalog')
groups.setdefault('Resources', []).append(assets)
resources.append(obj('build:assets', isa='PBXBuildFile', fileRef=assets))
for path in [
    'Vendor/AMapNaviKit.framework/AMap.bundle',
    'Vendor/AMapNaviKit.framework/AMapNavi.bundle',
    'Vendor/AMapNaviKit.framework/AMapNaviNavigationView.nib',
    'Vendor/AMapNaviKit.framework/AMapNaviPlanView.nib',
    'Vendor/AMapNaviPrivacy.bundle', 'Vendor/AMapSearchPrivacy.bundle', 'Vendor/AMapFoundationPrivacy.bundle'
]:
    ref = file(path, 'wrapper.nib' if path.endswith('.nib') else 'wrapper.plug-in')
    groups.setdefault('Vendor resources', []).append(ref)
    resources.append(obj('build:'+path, isa='PBXBuildFile', fileRef=ref))

app_product = obj('app-product', isa='PBXFileReference', explicitFileType='wrapper.application', path='LaneAhead.app', sourceTree='BUILT_PRODUCTS_DIR')
ui_product = obj('ui-product', isa='PBXFileReference', explicitFileType='wrapper.cfbundle', path='LaneAheadUITests.xctest', sourceTree='BUILT_PRODUCTS_DIR')
product_group = obj('products', isa='PBXGroup', name='Products', children=[app_product,ui_product], sourceTree='<group>')
children = [obj('group:'+name, isa='PBXGroup', name=name, children=refs, sourceTree='<group>') for name,refs in groups.items()]
children += [file('LaneAhead/Info.plist','text.plist.xml'), product_group]
main_group = obj('main-group', isa='PBXGroup', children=children, sourceTree='<group>')

script = obj('config-phase', isa='PBXShellScriptBuildPhase', buildActionMask=2147483647, files=[], inputPaths=['$(SRCROOT)/scripts/prepare-config.py'], outputPaths=['$(SRCROOT)/LaneAhead/Resources/MapKeys.plist'],
    runOnlyForDeploymentPostprocessing=0, shellPath='/bin/sh', shellScript='/usr/bin/python3 "$SRCROOT/scripts/prepare-config.py"\n', alwaysOutOfDate=1,
    name='Prepare local map configuration')
source_phase = obj('source-phase', isa='PBXSourcesBuildPhase', buildActionMask=2147483647, files=sources, runOnlyForDeploymentPostprocessing=0)
resource_phase = obj('resource-phase', isa='PBXResourcesBuildPhase', buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)
framework_phase = obj('framework-phase', isa='PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
system_frameworks = ['CoreMotion','CoreLocation','GLKit','SystemConfiguration','CoreTelephony','CoreServices','CallKit',
    'AVFoundation','AudioToolbox','VideoToolbox','Metal','QuartzCore','Security','WebKit','Accelerate','CoreGraphics','UIKit','Foundation']
device_links = ['$(inherited)','-ObjC','-lc++','-lz','-lsqlite3','-liconv','-lbz2','-lresolv']
for framework in ['AMapNaviKit','AMapFoundationKit','AMapSearchKit'] + system_frameworks: device_links += ['-framework',framework]
common = {'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0',
    'SWIFT_VERSION':'5.0','ENABLE_USER_SCRIPT_SANDBOXING':'NO','SWIFT_STRICT_CONCURRENCY':'minimal'}
app_settings = {'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'com.laneahead.ios','CODE_SIGN_STYLE':'Automatic',
    'MARKETING_VERSION':(root/'VERSION').read_text().strip(),'CURRENT_PROJECT_VERSION':'1','TARGETED_DEVICE_FAMILY':'1',
    'INFOPLIST_FILE':'LaneAhead/Info.plist','SWIFT_OBJC_BRIDGING_HEADER':'LaneAhead/Bridge/LaneAhead-Bridging-Header.h',
    'FRAMEWORK_SEARCH_PATHS':['$(inherited)','$(PROJECT_DIR)/Vendor'],'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon',
    'OTHER_LDFLAGS[sdk=iphoneos*]':device_links,'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator',
    'ENABLE_BITCODE':'NO','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],
    'SWIFT_EMIT_LOC_STRINGS':'YES'}

def configs(name, settings):
    refs = []
    for mode in ['Debug','Release']:
        more = {'SWIFT_OPTIMIZATION_LEVEL':'-Onone','DEBUG_INFORMATION_FORMAT':'dwarf','ENABLE_TESTABILITY':'YES',
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)'} if mode == 'Debug' else {
            'SWIFT_COMPILATION_MODE':'wholemodule','DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym'}
        refs.append(obj('config:'+name+mode, isa='XCBuildConfiguration', name=mode, buildSettings={**settings,**more}))
    return obj('configs:'+name, isa='XCConfigurationList', buildConfigurations=refs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')

app = obj('app', isa='PBXNativeTarget', name='LaneAhead', productName='LaneAhead', productReference=app_product,
    productType='com.apple.product-type.application', buildConfigurationList=configs('app',app_settings),
    buildPhases=[script,source_phase,framework_phase,resource_phase], buildRules=[], dependencies=[])
proxy = obj('proxy', isa='PBXContainerItemProxy', containerPortal=ident('project'), proxyType=1, remoteGlobalIDString=app, remoteInfo='LaneAhead')
dependency = obj('dependency', isa='PBXTargetDependency', target=app, targetProxy=proxy)
ui_sources=[]
for p in sorted((root/'Tests/UI').glob('*.swift')):
    ref=file(str(p.relative_to(root)),'sourcecode.swift')
    ui_sources.append(obj('ui-build:'+str(p),isa='PBXBuildFile',fileRef=ref))
    objects[main_group]['children'].append(ref)
ui_phase = obj('ui-phase',isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=ui_sources,runOnlyForDeploymentPostprocessing=0)
ui = obj('ui',isa='PBXNativeTarget',name='LaneAheadUITests',productName='LaneAheadUITests',productReference=ui_product,
    productType='com.apple.product-type.bundle.ui-testing',buildConfigurationList=configs('ui',{
        'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'com.laneahead.ios.uitests','CODE_SIGN_STYLE':'Automatic',
        'GENERATE_INFOPLIST_FILE':'YES','TARGETED_DEVICE_FAMILY':'1','TEST_TARGET_NAME':'LaneAhead'}),
    buildPhases=[ui_phase],buildRules=[],dependencies=[dependency])
obj('project',isa='PBXProject',attributes={'LastUpgradeCheck':'2600','BuildIndependentTargetsInParallel':'YES',
    'TargetAttributes':{app:{'CreatedOnToolsVersion':'26.0','ProvisioningStyle':'Automatic'},ui:{'CreatedOnToolsVersion':'26.0','TestTargetID':app}}},
    buildConfigurationList=configs('project',common),compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',
    knownRegions=['zh-Hans','en','Base'],hasScannedForEncodings=0,mainGroup=main_group,productRefGroup=product_group,
    projectDirPath='',projectRoot='',targets=[app,ui])
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+raw({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':ident('project')})+'\n')
scheme=project/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
def ref(target, product, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:LaneAhead.xcodeproj"/>'
(scheme/'LaneAhead.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(app,'LaneAhead.app','LaneAhead')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref(ui,'LaneAheadUITests.xctest','LaneAheadUITests')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app,'LaneAhead.app','LaneAhead')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app,'LaneAhead.app','LaneAhead')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated LaneAhead.xcodeproj')
