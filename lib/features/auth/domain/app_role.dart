enum AppRole {
  household('household', 'Household user'),
  business('business', 'Business user'),
  institution('institution', 'School or institution'),
  collector('collector', 'Waste collector'),
  driver('driver', 'Driver'),
  collectionCentreOperator(
    'collectionCentreOperator',
    'Collection centre operator',
  ),
  repairTechnician('repairTechnician', 'Repair technician'),
  recycler('recycler', 'Recycler'),
  administrator('administrator', 'Administrator'),
  environmentalOfficer('environmentalOfficer', 'Environmental officer'),
  superAdministrator('superAdministrator', 'Super administrator');

  const AppRole(this.value, this.label);

  final String value;
  final String label;

  static const selfServiceRoles = [household, business, institution];

  static AppRole fromValue(String? value) => values.firstWhere(
    (role) => role.value == value,
    orElse: () => AppRole.household,
  );
}
