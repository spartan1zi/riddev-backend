import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/dispute_screens.dart';
import '../screens/worker_screens.dart';

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>();

GoRouter createWorkerRouter() {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const WorkerSplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const WorkerLoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const WorkerRegisterScreen()),
      GoRoute(path: '/setup', builder: (_, _) => const WorkerProfileSetupScreen()),
      GoRoute(path: '/upload-documents', builder: (_, _) => const DocumentUploadScreen()),
      GoRoute(path: '/verification-pending', builder: (_, _) => const VerificationPendingScreen()),

      /// Main tabs share one scaffold (correct selected tab, no broken navigator stack).
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          final cs = Theme.of(context).colorScheme;
          return Scaffold(
            body: navigationShell,
            bottomNavigationBar: ColoredBox(
              color: cs.surfaceContainerLowest,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                  child: Material(
                    color: cs.surface,
                    elevation: 6,
                    shadowColor: cs.shadow.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(28),
                    clipBehavior: Clip.antiAlias,
                    child: NavigationBar(
                      selectedIndex: navigationShell.currentIndex,
                      onDestinationSelected: navigationShell.goBranch,
                      destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: 'Home',
                        tooltip: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.handyman_outlined),
                        selectedIcon: Icon(Icons.handyman_rounded),
                        label: 'Jobs',
                        tooltip: 'Jobs',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.savings_outlined),
                        selectedIcon: Icon(Icons.savings_rounded),
                        label: 'Earn',
                        tooltip: 'Earnings',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.person_outline_rounded),
                        selectedIcon: Icon(Icons.person_rounded),
                        label: 'Profile',
                        tooltip: 'Profile',
                      ),
                    ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (_, _) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/jobs',
                builder: (_, _) => const AvailableJobsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/earnings',
                builder: (_, _) => const EarningsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/worker-profile',
                builder: (_, _) => const WorkerProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // Full-screen routes (on top of shell)
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/notifications',
        builder: (_, _) => const WorkerNotificationsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/job/:jobId',
        builder: (_, state) =>
            WorkerJobDetailScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/job/:jobId/quote',
        builder: (_, state) =>
            SendQuoteScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/my-active-jobs',
        builder: (_, _) => const MyActiveJobsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/my-disputes',
        builder: (_, _) => const MyDisputesScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/dispute/:disputeId',
        builder: (_, state) =>
            DisputeThreadScreen(disputeId: state.pathParameters['disputeId']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/completed-jobs',
        builder: (_, _) => const WorkerCompletedJobsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/pending-jobs',
        builder: (_, _) => const WorkerPendingJobsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/active-job/:jobId',
        builder: (_, state) =>
            WorkerActiveJobScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/extra-cost/:jobId',
        builder: (_, state) =>
            ExtraCostRequestScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/chat/:jobId',
        builder: (_, state) =>
            WorkerChatScreen(jobId: state.pathParameters['jobId']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/earnings/detail',
        builder: (_, _) => const PayoutDetailScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/my-reviews',
        builder: (_, _) => const MyReviewsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/my-documents',
        builder: (_, _) => const WorkerDocumentsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/settings',
        builder: (_, _) => const WorkerSettingsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/disputes',
        builder: (_, _) => const WorkerDisputeCentreScreen(),
      ),
    ],
  );
}
