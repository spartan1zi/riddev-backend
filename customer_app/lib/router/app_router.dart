import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/active_job_screens.dart';
import '../screens/dispute_screens.dart';
import '../screens/auth_screens.dart';
import '../screens/home_screens.dart';
import '../screens/post_job_screens.dart';
import '../screens/quotes_payment_screens.dart';
import '../screens/wallet_screen.dart';

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>();

GoRouter createCustomerRouter() {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/post/category',
        builder: (_, state) => SelectCategoryScreen(
          initialExpandGroupId: state.uri.queryParameters['group'],
        ),
      ),
      GoRoute(path: '/post/details', builder: (_, _) => const JobDetailsScreen()),
      GoRoute(path: '/post/location', builder: (_, _) => const JobLocationScreen()),
      GoRoute(path: '/post/review', builder: (_, _) => const JobReviewScreen()),
      GoRoute(
        path: '/jobs/:jobId/quotes',
        builder: (_, state) => QuotesListScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        path: '/jobs/:jobId/negotiation',
        builder: (_, state) => NegotiationScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        path: '/jobs/:jobId/quote-accepted',
        builder: (_, state) => QuoteAcceptedScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        path: '/payment/:jobId',
        builder: (_, state) => PaymentScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        path: '/payment/:jobId/processing',
        builder: (_, state) => PaymentProcessingScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        path: '/payment/:jobId/success',
        builder: (_, state) => PaymentSuccessScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        path: '/active-job/:jobId',
        builder: (_, state) => ActiveJobScreen(
          jobId: state.pathParameters['jobId']!,
          fromPayment: state.uri.queryParameters['from'] == 'payment',
        ),
      ),
      GoRoute(
        path: '/chat/:jobId',
        builder: (_, state) => ChatScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        path: '/job-complete/:jobId',
        builder: (_, state) => JobCompleteScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        path: '/review/:jobId',
        builder: (_, state) => RateWorkerScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        path: '/history',
        builder: (_, state) {
          final f = state.uri.queryParameters['filter'];
          return JobHistoryScreen(
            activeOnly: f == 'active',
            completedOnly: f == 'completed',
          );
        },
      ),
      GoRoute(
        path: '/history/:jobId',
        builder: (_, state) => JobDetailHistoryScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(path: '/wallet', builder: (_, _) => const CustomerWalletScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/saved-workers', builder: (_, _) => const SavedWorkersScreen()),
      GoRoute(path: '/disputes', builder: (_, _) => const MyDisputesScreen()),
      GoRoute(
        path: '/dispute-thread/:disputeId',
        builder: (_, state) =>
            DisputeThreadScreen(disputeId: state.pathParameters['disputeId']!),
      ),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    ],
  );
}
