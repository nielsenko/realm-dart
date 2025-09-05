// Copyright 2021 MongoDB, Inc.
// SPDX-License-Identifier: Apache-2.0

import 'package:realm_common/realm_common.dart';
import 'package:source_gen/source_gen.dart';

const ignoredChecker = TypeChecker.typeNamed(Ignored);

const indexedChecker = TypeChecker.typeNamed(Indexed);

const mapToChecker = TypeChecker.typeNamed(MapTo);

const primaryKeyChecker = TypeChecker.typeNamed(PrimaryKey);

const backlinkChecker = TypeChecker.typeNamed(Backlink);

const realmAnnotationChecker = TypeChecker.any([ignoredChecker, indexedChecker, mapToChecker, primaryKeyChecker]);

const realmModelChecker = TypeChecker.typeNamed(RealmModel);
