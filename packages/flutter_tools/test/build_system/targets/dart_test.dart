// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/build.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/exceptions.dart';
import 'package:flutter_tools/src/build_system/targets/dart.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/compile.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:mockito/mockito.dart';
import 'package:process/process.dart';

import '../../src/common.dart';
import '../../src/mocks.dart';
import '../../src/testbed.dart';

void main() {
  group('dart rules', () {
    Testbed testbed;
    BuildSystem buildSystem;
    Environment androidEnvironment;
    Environment iosEnvironment;
    MockProcessManager mockProcessManager;

    setUpAll(() {
      Cache.disableLocking();
    });

    setUp(() {
      mockProcessManager = MockProcessManager();
      testbed = Testbed(setup: () {
        androidEnvironment = Environment(
          projectDir: fs.currentDirectory,
          defines: <String, String>{
            kBuildMode: getNameForBuildMode(BuildMode.profile),
            kTargetPlatform: getNameForTargetPlatform(TargetPlatform.android_arm),
          }
        );
        iosEnvironment = Environment(
          projectDir: fs.currentDirectory,
          defines: <String, String>{
            kBuildMode: getNameForBuildMode(BuildMode.profile),
            kTargetPlatform: getNameForTargetPlatform(TargetPlatform.ios),
          }
        );
        buildSystem = BuildSystem();
        HostPlatform hostPlatform;
        if (platform.isWindows) {
          hostPlatform = HostPlatform.windows_x64;
        } else if (platform.isLinux) {
          hostPlatform = HostPlatform.linux_x64;
        } else if (platform.isMacOS) {
           hostPlatform = HostPlatform.darwin_x64;
        } else {
          assert(false);
        }
         final String skyEngineLine = platform.isWindows
            ? r'sky_engine:file:///C:/bin/cache/pkg/sky_engine/lib/'
            : 'sky_engine:file:///bin/cache/pkg/sky_engine/lib/';
        fs.file('.packages')
          ..createSync()
          ..writeAsStringSync('''
# Generated
$skyEngineLine
flutter_tools:lib/''');
        final String engineArtifacts = fs.path.join('bin', 'cache',
            'artifacts', 'engine');
        final List<String> paths = <String>[
          fs.path.join('bin', 'cache', 'pkg', 'sky_engine', 'lib', 'ui',
            'ui.dart'),
          fs.path.join('bin', 'cache', 'pkg', 'sky_engine', 'sdk_ext',
              'vmservice_io.dart'),
          fs.path.join('bin', 'cache', 'dart-sdk', 'bin', 'dart'),
          fs.path.join(engineArtifacts, getNameForHostPlatform(hostPlatform),
              'frontend_server.dart.snapshot'),
          fs.path.join(engineArtifacts, 'android-arm-profile',
              getNameForHostPlatform(hostPlatform), 'gen_snapshot'),
          fs.path.join(engineArtifacts, 'ios-profile', 'gen_snapshot'),
          fs.path.join(engineArtifacts, 'common', 'flutter_patched_sdk',
              'platform_strong.dill'),
          fs.path.join('lib', 'foo.dart'),
          fs.path.join('lib', 'bar.dart'),
          fs.path.join('lib', 'fizz'),
        ];
        for (String path in paths) {
          fs.file(path).createSync(recursive: true);
        }
      }, overrides: <Type, Generator>{
        KernelCompilerFactory: () => FakeKernelCompilerFactory(),
        GenSnapshot: () => FakeGenSnapshot(),
      });
    });

    test('kernel_snapshot Produces correct output directory', () => testbed.run(() async {
      await buildSystem.build('kernel_snapshot', androidEnvironment, const BuildSystemConfig());

      expect(fs.file(fs.path.join(androidEnvironment.buildDir.path,'main.app.dill')).existsSync(), true);
    }));

    test('kernel_snapshot throws error if missing build mode', () => testbed.run(() async {
      final BuildResult result = await buildSystem.build('kernel_snapshot',
          androidEnvironment..defines.remove(kBuildMode), const BuildSystemConfig());

      expect(result.exceptions.values.single.exception, isInstanceOf<MissingDefineException>());
    }));

    test('aot_elf_profile Produces correct output directory', () => testbed.run(() async {
      await buildSystem.build('aot_elf_profile', androidEnvironment, const BuildSystemConfig());

      expect(fs.file(fs.path.join(androidEnvironment.buildDir.path, 'main.app.dill')).existsSync(), true);
      expect(fs.file(fs.path.join(androidEnvironment.buildDir.path, 'app.so')).existsSync(), true);
    }));

    test('aot_elf_profile throws error if missing build mode', () => testbed.run(() async {
      final BuildResult result = await buildSystem.build('aot_elf_profile',
          androidEnvironment..defines.remove(kBuildMode), const BuildSystemConfig());

      expect(result.exceptions.values.single.exception, isInstanceOf<MissingDefineException>());
    }));


    test('aot_elf_profile throws error if missing target platform', () => testbed.run(() async {
      final BuildResult result = await buildSystem.build('aot_elf_profile',
          androidEnvironment..defines.remove(kTargetPlatform), const BuildSystemConfig());

      expect(result.exceptions.values.single.exception, isInstanceOf<MissingDefineException>());
    }));


    test('aot_assembly_profile throws error if missing build mode', () => testbed.run(() async {
      final BuildResult result = await buildSystem.build('aot_assembly_profile',
          iosEnvironment..defines.remove(kBuildMode), const BuildSystemConfig());

      expect(result.exceptions.values.single.exception, isInstanceOf<MissingDefineException>());
    }));

    test('aot_assembly_profile throws error if missing target platform', () => testbed.run(() async {
      final BuildResult result = await buildSystem.build('aot_assembly_profile',
          iosEnvironment..defines.remove(kTargetPlatform), const BuildSystemConfig());

      expect(result.exceptions.values.single.exception, isInstanceOf<MissingDefineException>());
    }));

    test('aot_assembly_profile throws error if built for non-iOS platform', () => testbed.run(() async {
      final BuildResult result = await buildSystem.build('aot_assembly_profile',
          androidEnvironment, const BuildSystemConfig());

      expect(result.exceptions.values.single.exception, isInstanceOf<Exception>());
    }));

    test('aot_assembly_profile will lipo binaries together when multiple archs are requested', () => testbed.run(() async {
      iosEnvironment.defines[kIosArchs] ='armv7,arm64';
      when(mockProcessManager.run(any)).thenAnswer((Invocation invocation) async {
        fs.file(fs.path.join(iosEnvironment.buildDir.path, 'App.framework', 'App'))
            .createSync(recursive: true);
        return FakeProcessResult(
          stdout: '',
          stderr: '',
        );
      });
      final BuildResult result = await buildSystem.build('aot_assembly_profile',
          iosEnvironment, const BuildSystemConfig());

      expect(result.success, true);
    }, overrides: <Type, Generator>{
      ProcessManager: () => mockProcessManager,
    }));
  });
}

class MockProcessManager extends Mock implements ProcessManager {}

class FakeGenSnapshot implements GenSnapshot {
  @override
  Future<int> run({SnapshotType snapshotType, IOSArch iosArch, Iterable<String> additionalArgs = const <String>[]}) async {
    final Directory out = fs.file(additionalArgs.last).parent;
    if (iosArch == null) {
      out.childFile('app.so').createSync();
      out.childFile('gen_snapshot.d').createSync();
      return 0;
    }
    out.childDirectory('App.framework').childFile('App').createSync(recursive: true);
    out.childFile('snapshot_assembly.S').createSync();
    out.childFile('snapshot_assembly.o').createSync();
    return 0;
  }
}

class FakeKernelCompilerFactory implements KernelCompilerFactory {
  FakeKernelCompiler kernelCompiler = FakeKernelCompiler();

  @override
  Future<KernelCompiler> create(FlutterProject flutterProject) async {
    return kernelCompiler;
  }
}

class FakeKernelCompiler implements KernelCompiler {
  @override
  Future<CompilerOutput> compile({
    String sdkRoot,
    String mainPath,
    String outputFilePath,
    String depFilePath,
    TargetModel targetModel = TargetModel.flutter,
    bool linkPlatformKernelIn = false,
    bool aot = false,
    bool trackWidgetCreation,
    List<String> extraFrontEndOptions,
    String incrementalCompilerByteStorePath,
    String packagesPath,
    List<String> fileSystemRoots,
    String fileSystemScheme,
    bool targetProductVm = false,
    String initializeFromDill}) async {
      fs.file(outputFilePath).createSync(recursive: true);
      return CompilerOutput(outputFilePath, 0, null);
  }
}
