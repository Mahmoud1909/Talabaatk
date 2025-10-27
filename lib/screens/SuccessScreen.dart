import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:talabak_users/screens/main_screen.dart';

class SuccessScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF25AA50), // red background
      body: Center(
        child: Lottie.asset(
          'assets/animations/success.json',
          width: 400,
          height: 400,
          repeat: false,
          onLoaded: (composition) {
            // Wait until animation is done, then navigate
            Future.delayed(composition.duration, () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => MainScreen()),
              );
            });
          },
        ),
      ),
    );
  }
}
