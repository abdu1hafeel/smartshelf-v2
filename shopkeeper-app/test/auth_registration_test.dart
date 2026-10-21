// ==============================================================================
// SmartShelf V2 - User Registration & Onboarding Unit and Widget Tests
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_app/models/organization.dart';
import 'package:shopkeeper_app/screens/auth_screen.dart';
import 'package:shopkeeper_app/screens/onboarding_screen.dart';
import 'package:shopkeeper_app/screens/signup_screen.dart';
import 'package:shopkeeper_app/services/auth_service.dart';

void main() {
  group('SignUpResult Model Tests', () {
    test('Successful signup result with direct session', () {
      const res = SignUpResult(success: true, requiresEmailConfirmation: false);
      expect(res.success, isTrue);
      expect(res.requiresEmailConfirmation, isFalse);
      expect(res.message, isNull);
    });

    test('Successful signup result requiring email confirmation', () {
      const res = SignUpResult(
        success: true,
        requiresEmailConfirmation: true,
        message: 'Please check your email to verify your account.',
      );
      expect(res.success, isTrue);
      expect(res.requiresEmailConfirmation, isTrue);
      expect(res.message, contains('verify your account'));
    });

    test('Failed signup result', () {
      const res = SignUpResult(
        success: false,
        message: 'An account with this email address already exists.',
      );
      expect(res.success, isFalse);
      expect(res.requiresEmailConfirmation, isFalse);
      expect(res.message, contains('already exists'));
    });
  });

  group('SignupScreen Widget Tests', () {
    testWidgets('Renders all input fields, buttons, and sign in link',
        (WidgetTester tester) async {
      final authService = AuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: SignupScreen(authService: authService),
        ),
      );

      // Verify header and titles
      expect(find.text('Create Account'), findsWidgets);
      expect(find.text('Join your store team or register a new retail branch'), findsOneWidget);

      // Verify form fields
      expect(find.widgetWithText(TextFormField, 'Full Name'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Email Address'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Confirm Password'), findsOneWidget);

      // Verify submit button & sign in link
      expect(find.widgetWithText(ElevatedButton, 'Create Account'), findsOneWidget);
      expect(find.text('Already have an account?'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Sign In'), findsOneWidget);
    });

    testWidgets('Validates empty fields on submission',
        (WidgetTester tester) async {
      final authService = AuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: SignupScreen(authService: authService),
        ),
      );

      // Tap submit with empty form
      final submitBtn = find.widgetWithText(ElevatedButton, 'Create Account');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter your full name'), findsOneWidget);
      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please enter a password'), findsOneWidget);
      expect(find.text('Please confirm your password'), findsOneWidget);
    });

    testWidgets('Validates invalid email format and short password',
        (WidgetTester tester) async {
      final authService = AuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: SignupScreen(authService: authService),
        ),
      );

      // Enter name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name'),
        'Test User',
      );

      // Enter invalid email
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email Address'),
        'invalid-email-format',
      );

      // Enter short password
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        '123',
      );

      // Enter matching confirm password
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password'),
        '123',
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email address'), findsOneWidget);
      expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    });

    testWidgets('Validates password and confirm password mismatch',
        (WidgetTester tester) async {
      final authService = AuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: SignupScreen(authService: authService),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name'),
        'Test User',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email Address'),
        'valid@store.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'Password123!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password'),
        'DifferentPass456!',
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match'), findsOneWidget);
    });
  });

  group('AuthScreen Forgot Password & Navigation Tests', () {
    testWidgets('Renders Forgot Password link and opens dialog',
        (WidgetTester tester) async {
      final authService = AuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: AuthScreen(authService: authService),
        ),
      );

      // Verify Sign Up link is present
      expect(find.widgetWithText(TextButton, 'Sign Up'), findsOneWidget);

      // Verify Forgot Password button is present
      final forgotBtn = find.widgetWithText(TextButton, 'Forgot Password?');
      expect(forgotBtn, findsOneWidget);

      await tester.tap(forgotBtn);
      await tester.pumpAndSettle();

      // Verify reset password dialog opened
      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.text('Send Link'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('OnboardingScreen Widget Tests', () {
    testWidgets('Renders Join with Code tab and validates empty invite code',
        (WidgetTester tester) async {
      final authService = AuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            authService: authService,
            onStoreJoined: () {},
          ),
        ),
      );

      expect(find.text('Store Onboarding'), findsOneWidget);
      expect(find.text('Join with Code'), findsOneWidget);
      expect(find.text('Create New Store'), findsOneWidget);

      // Tap validate and join
      final joinBtn = find.widgetWithText(ElevatedButton, 'Validate & Join Store');
      expect(joinBtn, findsOneWidget);
      await tester.ensureVisible(joinBtn);
      await tester.tap(joinBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter your invitation code'), findsOneWidget);
    });

    testWidgets('Switches to Create New Store tab and validates business names',
        (WidgetTester tester) async {
      final authService = AuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            authService: authService,
            onStoreJoined: () {},
          ),
        ),
      );

      // Switch to Create New Store tab
      await tester.tap(find.text('Create New Store'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Organization / Business Name'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Store Branch Name'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Location / City (Optional)'), findsOneWidget);

      // Tap submit with empty form
      final createBtn = find.widgetWithText(ElevatedButton, 'Provision Store & Organization');
      expect(createBtn, findsOneWidget);
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter business name'), findsOneWidget);
      expect(find.text('Please enter store branch name'), findsOneWidget);
    });

    testWidgets('Renders existing organization selector and disambiguates duplicate names',
        (WidgetTester tester) async {
      final authService = AuthService();
      final org1 = Organization(
        id: '2c17c6c2-83fc-453a-b2e2-8ec289795e3b',
        name: 'SAHARA',
        createdAt: DateTime.now(),
      );
      final org2 = Organization(
        id: '432ab506-9999-8888-7777-666655554444',
        name: 'SAHARA',
        createdAt: DateTime.now(),
      );
      authService.setManagedOrganizationsForTesting([org1, org2]);

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            authService: authService,
            onStoreJoined: () {},
          ),
        ),
      );

      // Switch to Create New Store tab
      await tester.tap(find.text('Create New Store'));
      await tester.pumpAndSettle();

      // Verify mode switcher is visible
      expect(find.byKey(const Key('mode_existing_org')), findsOneWidget);
      expect(find.byKey(const Key('mode_new_org')), findsOneWidget);

      // Verify header and dropdown
      expect(find.text('Add Store to Existing Organization'), findsOneWidget);
      expect(find.byKey(const Key('org_dropdown')), findsOneWidget);

      // Verify button says "Add Store to Organization"
      final addBtn = find.widgetWithText(ElevatedButton, 'Add Store to Organization');
      expect(addBtn, findsOneWidget);

      // Open dropdown to verify items and disambiguation
      await tester.tap(find.byKey(const Key('org_dropdown')));
      await tester.pumpAndSettle();

      expect(find.text('SAHARA (2c17c6c2)'), findsWidgets);
      expect(find.text('SAHARA (432ab506)'), findsWidgets);

      // Close dropdown by tapping outside
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Tap submit with empty store branch name
      await tester.ensureVisible(addBtn);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter store branch name'), findsOneWidget);
    });

    testWidgets('Toggles between Existing Organization and New Organization modes',
        (WidgetTester tester) async {
      final authService = AuthService();
      final org = Organization(
        id: '2c17c6c2-83fc-453a-b2e2-8ec289795e3b',
        name: 'SAHARA',
        createdAt: DateTime.now(),
      );
      authService.setManagedOrganizationsForTesting([org]);

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            authService: authService,
            onStoreJoined: () {},
          ),
        ),
      );

      // Switch to Create tab
      await tester.tap(find.text('Create New Store'));
      await tester.pumpAndSettle();

      // Initially in Existing Organization mode
      expect(find.byKey(const Key('org_dropdown')), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Add Store to Organization'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Organization / Business Name'), findsNothing);

      // Switch to New Organization mode
      await tester.tap(find.byKey(const Key('mode_new_org')));
      await tester.pumpAndSettle();

      // Form now shows business name input and provision button
      expect(find.byKey(const Key('org_dropdown')), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Organization / Business Name'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Provision Store & Organization'), findsOneWidget);

      // Switch back to Existing Organization mode
      await tester.tap(find.byKey(const Key('mode_existing_org')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('org_dropdown')), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Add Store to Organization'), findsOneWidget);
    });
  });
}
