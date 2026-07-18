import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../domain/app_role.dart';
import '../domain/user_profile.dart';
import '../../organizations/data/organization_repository.dart';
import '../../organizations/presentation/organization_screens.dart';
import '../../pickups/data/pickup_repository.dart';
import '../../pickups/presentation/pickup_screens.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/presentation/inventory_screens.dart';
import '../../dispatch/data/dispatch_repository.dart';
import '../../dispatch/presentation/dispatch_screens.dart';
import '../../fleet/data/fleet_repository.dart';
import '../../fleet/presentation/fleet_screens.dart';
import '../../routing/data/route_repository.dart';
import '../../routing/presentation/route_screens.dart';
import '../../centres/data/collection_centre_repository.dart';
import '../../centres/presentation/collection_centre_screens.dart';
import '../../repairs/data/repair_repository.dart';
import '../../repairs/presentation/repair_screens.dart';
import '../../recycling/data/recycling_repository.dart';
import '../../recycling/presentation/recycling_screens.dart';
import '../../recovery/data/resource_recovery_repository.dart';
import '../../recovery/presentation/resource_recovery_screens.dart';
import '../../hazardous/data/hazardous_waste_repository.dart';
import '../../hazardous/presentation/hazardous_waste_screens.dart';
import '../../reverse_logistics/data/reverse_logistics_repository.dart';
import '../../reverse_logistics/presentation/reverse_logistics_screens.dart';
import '../../environmental_impact/data/environmental_impact_repository.dart';
import '../../environmental_impact/presentation/environmental_impact_screens.dart';
import '../../support/data/support_repository.dart';
import '../../support/presentation/support_screens.dart';
import '../../compliance/data/compliance_repository.dart';
import '../../compliance/presentation/compliance_screens.dart';
import '../../partners/data/partner_repository.dart';
import '../../partners/presentation/partner_screens.dart';
import '../../marketplace/data/marketplace_repository.dart';
import '../../marketplace/presentation/marketplace_screens.dart';
import '../../donations/data/donation_repository.dart';
import '../../donations/presentation/donation_screens.dart';
import '../../rewards/data/rewards_repository.dart';
import '../../rewards/presentation/rewards_screen.dart';
import '../../billing/data/billing_repository.dart';
import '../../billing/presentation/billing_screen.dart';
import '../../analytics/data/analytics_repository.dart';
import '../../analytics/presentation/analytics_reporting_screen.dart';
import '../../notifications/data/notification_repository.dart';
import '../../notifications/presentation/notification_screen.dart';
import '../../incidents/data/incident_repository.dart';
import '../../incidents/presentation/incident_screens.dart';
import '../../documents/data/document_repository.dart';
import '../../documents/presentation/document_screens.dart';
import '../../admin/data/admin_repository.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';
import '../../audit/data/audit_repository.dart';

String _errorMessage(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-credential' => 'The email or password is incorrect.',
      'email-already-in-use' => 'An account already uses this email address.',
      'invalid-email' => 'Enter a valid email address.',
      'weak-password' => 'Use a stronger password with at least 8 characters.',
      'too-many-requests' => 'Too many attempts. Please wait and try again.',
      _ => error.message ?? 'Authentication failed.',
    };
  }
  return error.toString().replaceFirst('Bad state: ', '');
}

class _AuthFrame extends StatelessWidget {
  const _AuthFrame({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.recycling,
                      size: 54,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'EcoTrace',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 28),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.repository});
  final AuthRepository repository;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.repository.signIn(
        email: _email.text,
        password: _password.text,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthFrame(
    title: 'Sign in to continue',
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (value) => value == null || !value.contains('@')
                ? 'Enter a valid email.'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) =>
                value == null || value.isEmpty ? 'Enter your password.' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ResetPasswordScreen(repository: widget.repository),
                      ),
                    ),
              child: const Text('Forgot password?'),
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Sign in'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          RegisterScreen(repository: widget.repository),
                    ),
                  ),
            child: const Text('Create account'),
          ),
        ],
      ),
    ),
  );
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.repository});
  final AuthRepository repository;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  AppRole _role = AppRole.household;
  bool _accepted = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_accepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Accept the terms and privacy policy to continue.'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.register(
        displayName: _name.text,
        email: _email.text,
        password: _password.text,
        role: _role,
        acceptedTerms: _accepted,
      );
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthFrame(
    title: 'Create your account',
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (value) => value == null || value.trim().length < 2
                ? 'Enter your name.'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (value) => value == null || !value.contains('@')
                ? 'Enter a valid email.'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline),
              helperText: 'At least 8 characters',
            ),
            validator: (value) => value == null || value.length < 8
                ? 'Use at least 8 characters.'
                : null,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<AppRole>(
            initialValue: _role,
            decoration: const InputDecoration(
              labelText: 'Account type',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            items: AppRole.selfServiceRoles
                .map(
                  (role) =>
                      DropdownMenuItem(value: role, child: Text(role.label)),
                )
                .toList(),
            onChanged: _busy ? null : (role) => setState(() => _role = role!),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _accepted,
            onChanged: _busy
                ? null
                : (value) => setState(() => _accepted = value ?? false),
            title: const Text(
              'I accept the Terms of Service and Privacy Policy.',
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create account'),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    ),
  );
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.repository});
  final AuthRepository repository;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_email.text.contains('@')) return;
    setState(() => _busy = true);
    try {
      await widget.repository.sendPasswordReset(_email.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'If the account exists, a reset email has been sent.',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthFrame(
    title: 'Reset your password',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: const Text('Send reset email'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.repository,
    required this.user,
  });
  final AuthRepository repository;
  final User user;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MessageScreen(
    title: 'Verify your email',
    message:
        'We sent a verification link to ${widget.user.email}. Open it, then return here.',
    actionLabel: _busy ? 'Checking…' : 'I have verified my email',
    onAction: _busy
        ? null
        : () => _run(
            widget.repository.refreshUser,
            'Verification status refreshed.',
          ),
    secondaryLabel: 'Resend email',
    onSecondary: _busy
        ? null
        : () => _run(
            widget.repository.sendEmailVerification,
            'Verification email sent.',
          ),
    footer: TextButton(
      onPressed: _busy ? null : widget.repository.signOut,
      child: const Text('Use another account'),
    ),
  );
}

class RoleHomeScreen extends StatelessWidget {
  const RoleHomeScreen({
    super.key,
    required this.repository,
    required this.profile,
  });
  final AuthRepository repository;
  final UserProfile profile;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('EcoTrace'),
      actions: [
        IconButton(
          onPressed: repository.signOut,
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Icon(Icons.verified_user_outlined, size: 72),
              const SizedBox(height: 18),
              Text(
                'Welcome, ${profile.displayName}',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Chip(
                avatar: const Icon(Icons.badge_outlined),
                label: Text(profile.role.label),
              ),
              const SizedBox(height: 16),
              Text(
                'Your verified ${profile.role.label.toLowerCase()} workspace is ready.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 280,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrganizationListScreen(
                        repository: OrganizationRepository(),
                        userId: profile.uid,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.apartment),
                  label: const Text('Manage organizations'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 280,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PickupListScreen(
                        uid: profile.uid,
                        repository: PickupRepository(),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('E-waste pickups'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 280,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SupportDashboardScreen(
                        repository: SupportRepository(),
                        currentUserId: profile.uid,
                        currentUserName: profile.displayName.isEmpty
                            ? profile.email
                            : profile.displayName,
                        isAgent:
                            profile.role == AppRole.administrator ||
                            profile.role == AppRole.superAdministrator,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.support_agent),
                  label: const Text('Customer support'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 280,
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MarketplaceScreen(
                        repository: MarketplaceRepository(),
                        currentUserId: profile.uid,
                        currentUserName: profile.displayName.isEmpty
                            ? profile.email
                            : profile.displayName,
                        currentUserEmail: profile.email,
                        canListDevices: [
                          AppRole.repairTechnician,
                          AppRole.environmentalOfficer,
                          AppRole.administrator,
                          AppRole.superAdministrator,
                        ].contains(profile.role),
                        canListMaterials: [
                          AppRole.recycler,
                          AppRole.environmentalOfficer,
                          AppRole.administrator,
                          AppRole.superAdministrator,
                        ].contains(profile.role),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Circular marketplace'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 280,
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DonationDashboardScreen(
                        repository: DonationRepository(),
                        userId: profile.uid,
                        canManage: [
                          AppRole.environmentalOfficer,
                          AppRole.administrator,
                          AppRole.superAdministrator,
                        ].contains(profile.role),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.volunteer_activism_outlined),
                  label: const Text('Donations and social impact'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 280,
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RewardsScreen(
                        repository: RewardsRepository(),
                        userId: profile.uid,
                        canManage: [
                          AppRole.environmentalOfficer,
                          AppRole.administrator,
                          AppRole.superAdministrator,
                        ].contains(profile.role),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Green rewards'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 280,
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BillingScreen(
                        repository: BillingRepository(),
                        userId: profile.uid,
                        canManage: [
                          AppRole.administrator,
                          AppRole.superAdministrator,
                        ].contains(profile.role),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Payments and billing'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 280,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NotificationScreen(
                        repository: NotificationRepository(),
                        uid: profile.uid,
                        canManage: [
                          AppRole.administrator,
                          AppRole.superAdministrator,
                        ].contains(profile.role),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Notifications'),
                ),
              ),
              if ([
                AppRole.collector,
                AppRole.driver,
                AppRole.collectionCentreOperator,
                AppRole.repairTechnician,
                AppRole.recycler,
                AppRole.environmentalOfficer,
                AppRole.administrator,
                AppRole.superAdministrator,
              ].contains(profile.role)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => IncidentDashboardScreen(
                          repository: IncidentRepository(),
                          userId: profile.uid,
                          canManage: [
                            AppRole.environmentalOfficer,
                            AppRole.administrator,
                            AppRole.superAdministrator,
                          ].contains(profile.role),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.health_and_safety_outlined),
                    label: const Text('Incident and safety'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: 280,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DocumentDashboardScreen(
                        repository: DocumentRepository(),
                        userId: profile.uid,
                        userName: profile.displayName.isEmpty
                            ? profile.email
                            : profile.displayName,
                        canGovern: [
                          AppRole.environmentalOfficer,
                          AppRole.administrator,
                          AppRole.superAdministrator,
                        ].contains(profile.role),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.folder_copy_outlined),
                  label: const Text('Document management'),
                ),
              ),
              if ([
                AppRole.environmentalOfficer,
                AppRole.administrator,
                AppRole.superAdministrator,
              ].contains(profile.role)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AnalyticsReportingScreen(
                          repository: AnalyticsRepository(),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('Analytics and reports'),
                  ),
                ),
              ],
              if (profile.role == AppRole.administrator ||
                  profile.role == AppRole.superAdministrator) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AdministrationDashboardScreen(
                          repository: AdminRepository(),
                          auditRepository: AuditRepository(),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Administration and audit'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrganizationReviewScreen(
                          repository: OrganizationRepository(),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Review organizations'),
                  ),
                ),
              ],
              if ([
                AppRole.collector,
                AppRole.collectionCentreOperator,
                AppRole.repairTechnician,
                AppRole.recycler,
                AppRole.environmentalOfficer,
                AppRole.administrator,
                AppRole.superAdministrator,
              ].contains(profile.role)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => InventoryScreen(
                          repository: InventoryRepository(),
                          canApprove: [
                            AppRole.environmentalOfficer,
                            AppRole.administrator,
                            AppRole.superAdministrator,
                          ].contains(profile.role),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('E-waste inventory'),
                  ),
                ),
              ],
              if ([
                AppRole.repairTechnician,
                AppRole.environmentalOfficer,
                AppRole.administrator,
                AppRole.superAdministrator,
              ].contains(profile.role)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RepairDashboardScreen(
                          repository: RepairRepository(),
                          inventoryRepository: InventoryRepository(),
                          currentUserId: profile.uid,
                          canApprove: [
                            AppRole.environmentalOfficer,
                            AppRole.administrator,
                            AppRole.superAdministrator,
                          ].contains(profile.role),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.handyman_outlined),
                    label: const Text('Repair and refurbishment'),
                  ),
                ),
              ],
              if ([
                AppRole.recycler,
                AppRole.environmentalOfficer,
                AppRole.administrator,
                AppRole.superAdministrator,
              ].contains(profile.role)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RecyclingDashboardScreen(
                          repository: RecyclingRepository(),
                          inventoryRepository: InventoryRepository(),
                          currentUserId: profile.uid,
                          canVerify: [
                            AppRole.environmentalOfficer,
                            AppRole.administrator,
                            AppRole.superAdministrator,
                          ].contains(profile.role),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.recycling),
                    label: const Text('Recycling processes'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ResourceRecoveryDashboardScreen(
                          repository: ResourceRecoveryRepository(),
                          currentUserId: profile.uid,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.precision_manufacturing_outlined),
                    label: const Text('Resource recovery'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HazardousWasteDashboardScreen(
                          repository: HazardousWasteRepository(),
                          currentUserId: profile.uid,
                          canCertify: [
                            AppRole.environmentalOfficer,
                            AppRole.administrator,
                            AppRole.superAdministrator,
                          ].contains(profile.role),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.warning_amber_outlined),
                    label: const Text('Hazardous waste'),
                  ),
                ),
              ],
              if ([
                AppRole.collectionCentreOperator,
                AppRole.administrator,
                AppRole.superAdministrator,
              ].contains(profile.role)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CollectionCentreDashboardScreen(
                          repository: CollectionCentreRepository(),
                          currentUserId: profile.uid,
                          canRegister: true,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.warehouse_outlined),
                    label: const Text('Collection centres'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DispatchDashboardScreen(
                          repository: DispatchRepository(),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.route),
                    label: const Text('Collection dispatch'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            FleetScreen(repository: FleetRepository()),
                      ),
                    ),
                    icon: const Icon(Icons.local_shipping),
                    label: const Text('Fleet management'),
                  ),
                ),
              ],
              if ([
                AppRole.environmentalOfficer,
                AppRole.administrator,
                AppRole.superAdministrator,
              ].contains(profile.role)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SustainabilityDashboardScreen(
                          repository: EnvironmentalImpactRepository(),
                          currentUserId: profile.uid,
                          canSaveReports: true,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.eco_outlined),
                    label: const Text('Environmental impact'),
                  ),
                ),
              ],
              if ([
                AppRole.environmentalOfficer,
                AppRole.administrator,
                AppRole.superAdministrator,
              ].contains(profile.role)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PartnerDashboardScreen(
                          repository: PartnerRepository(),
                          currentUserId: profile.uid,
                          canManage: true,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.handshake_outlined),
                    label: const Text('Partners and vendors'),
                  ),
                ),
              ],
              if ([
                AppRole.environmentalOfficer,
                AppRole.administrator,
                AppRole.superAdministrator,
              ].contains(profile.role)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ComplianceDashboardScreen(
                          repository: ComplianceRepository(),
                          currentUserId: profile.uid,
                          canManage: true,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.policy_outlined),
                    label: const Text('Compliance and regulatory'),
                  ),
                ),
              ],
              if ([
                AppRole.collector,
                AppRole.driver,
                AppRole.collectionCentreOperator,
                AppRole.repairTechnician,
                AppRole.recycler,
                AppRole.environmentalOfficer,
                AppRole.administrator,
                AppRole.superAdministrator,
              ].contains(profile.role)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReverseLogisticsDashboardScreen(
                          repository: ReverseLogisticsRepository(),
                          currentUserId: profile.uid,
                          isDriver: profile.role == AppRole.driver,
                          canCreate: [
                            AppRole.collectionCentreOperator,
                            AppRole.environmentalOfficer,
                            AppRole.administrator,
                            AppRole.superAdministrator,
                          ].contains(profile.role),
                          canApprove: [
                            AppRole.collectionCentreOperator,
                            AppRole.environmentalOfficer,
                            AppRole.administrator,
                            AppRole.superAdministrator,
                          ].contains(profile.role),
                          canReceive: [
                            AppRole.collectionCentreOperator,
                            AppRole.repairTechnician,
                            AppRole.recycler,
                            AppRole.environmentalOfficer,
                            AppRole.administrator,
                            AppRole.superAdministrator,
                          ].contains(profile.role),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Reverse logistics'),
                  ),
                ),
              ],
              if ([
                AppRole.driver,
                AppRole.collectionCentreOperator,
                AppRole.administrator,
                AppRole.superAdministrator,
              ].contains(profile.role)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RouteDashboardScreen(
                          repository: RouteRepository(),
                          canOptimize: profile.role != AppRole.driver,
                          currentUserId: profile.uid,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.navigation),
                    label: const Text('Routes and GPS'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class MessageScreen extends StatelessWidget {
  const MessageScreen({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.footer,
  });
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function()? onAction;
  final String? secondaryLabel;
  final Future<void> Function()? onSecondary;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => _AuthFrame(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
        if (secondaryLabel != null)
          TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
        ?footer,
      ],
    ),
  );
}
