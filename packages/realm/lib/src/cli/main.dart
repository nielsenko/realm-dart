// Copyright 2021 MongoDB, Inc.
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:args/command_runner.dart';

import 'generate/generate_command.dart';

void main(List<String> arguments) {
  CommandRunner<void>("dart run realm", 'Realm commands for working with the Realm SDK.')
    ..addCommand(GenerateCommand())
    ..run(arguments).catchError((Object error) {
      if (error is UsageException) {
        print(error);
        exit(64); // Exit code 64 indicates a usage error.
      }
      throw error;
    });
}
