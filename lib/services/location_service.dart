import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart';

class LocationService {
  static Future<String?> getCurrentCountryCode() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Check if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return null;
    }

    // 2. Request permission
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return null;
    }

    // 3. Get Position
    try {
      final position = await Geolocator.getCurrentPosition();

      // 4. Get Placemark/Country Code
      // Note: geocoding package might not support all platforms (e.g. Windows without config)
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS)) {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          return placemarks
              .first
              .isoCountryCode; // Returns 2-letter code e.g. "US", "IN"
        }
      } else {
        // Fallback or implementation for Web/Windows if geocoding not supported directly
        // For now return null or implement an API call fallback if really needed.
        // But user requirement was "ask for location permission", so we did that part provided we are on mobile.
        // On Windows, Geolocator works but Geocoding might not.

        // Try anyway, catch error
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          );
          if (placemarks.isNotEmpty) {
            return placemarks.first.isoCountryCode;
          }
        } catch (e) {
          debugPrint('Geocoding not supported on this platform: $e');
        }
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }

    return null;
  }
}
