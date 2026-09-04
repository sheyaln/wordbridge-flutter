import 'package:flutter/material.dart';

/// Nothing, because there is no file to draw.
///
/// Only a photo somebody took and a drawing fetched on demand arrive by this
/// route, and neither is reachable on a host with no files — so a button that
/// asks for one is a button whose picture was never written. The label alone
/// is a working button.
Widget symbolFromFile(String path, {required bool isSvg}) =>
    const SizedBox.shrink();
