load("//dart:build_defs.bzl", "dart_library")
load("//mobile/flutter/build_defs:flutter.bzl", "flutter_test_suite")

package(default_visibility = ["//visibility:public"])

licenses(["notice"])  # BSD

exports_files(["LICENSE"])

dart_library(
    name = "provide",
    srcs = glob(["lib/**/*.dart"]),
    license_files = ["LICENSE"],
    platforms = ["flutter"],
    deps = [
        "//third_party/dart/flutter",
    ],
)

flutter_test_suite(
    name = "tests",
    srcs = glob(["test/**/*.dart"]),
    deps = [
        ":provide",
        "//third_party/dart/flutter",
        "//third_party/dart/flutter_test",
        "//third_party/dart/mockito",
        "//third_party/dart/scoped_model",
        "//third_party/dart/test",
    ],
)
