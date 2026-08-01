# EcoTrace waste management system

EcoTrace is a Flutter and Firebase e-waste operations platform. It includes pickups, inventory and traceability, dispatch/fleet routing, driver GPS tracking, organizations, and collection-centre management.

The platform is being migrated to a secured REST API so Flutter clients no
longer own business-data access. See [the API architecture and local setup](docs/api-architecture.md).

## Collection centre management

Collection centre operators and administrators can register centres; configure contact details, GPS coordinates, operating hours, supported waste categories, storage capacity, and alert thresholds; manage storage sections and staff; check stock in and out; verify weights; review stock movements; record safety inspections; and monitor centre/network performance.

## Repair and refurbishment management

Repair technicians and supervisors can create repair assessments, assign technicians, diagnose faults, estimate and approve costs, record spare parts, track progress, perform quality control, grade refurbished devices, manage warranties, and approve donation or resale. Repair outcomes automatically synchronize the associated inventory item's processing state.

## Recycling process management

Recyclers can create facility batches from approved inventory, sort and dismantle items, record component separation, recovered and hazardous weights, processing losses, and final disposal. The workflow enforces batch mass balance, supports supervisor completion verification, and generates recycling certificates and performance reports.

## Resource recovery management

Recovered copper, aluminium, steel, plastic, glass, gold, silver, lithium, cobalt, and circuit boards are tracked by source batch, weight, quantity, grade, storage, market value, buyer, transfer, and sale status. Dashboards report inventory value, recovery efficiency, and realized revenue.

## Hazardous waste management

Hazardous components are identified and classified with special storage, safety instructions, PPE and battery-handling checks. The module records incidents and emergency response, compliance documents, staff training, licensed transfers and disposal, and supervisor-issued hazardous-waste certificates.

## Reverse logistics management

Reverse transfer orders track pickup-to-centre, centre-to-repair, centre-to-recycler, and inter-facility movements. Each order includes transport documentation, supervisor approval, vehicle and driver assignment, dispatch and receipt confirmation, photographic delivery proof, exception handling, an immutable chain of custody, printable manifests, and performance analytics.

## Environmental impact management

Environmental officers and administrators can monitor collected and recycled e-waste, landfill diversion, material recovery, safely handled hazardous waste, reusable devices, estimated carbon and energy savings, trees-equivalent impact, and estimated water-pollution reduction. The sustainability dashboard compares monthly performance and produces printable or saved environmental impact reports with a documented factor version.

## Customer support and complaint management

Every authenticated user has a support centre for enquiries and complaints, categorized tickets, evidence attachments, status tracking, public conversations, resolution, reopening, satisfaction ratings, FAQs, and knowledge-base guidance. Administrators can assign agents, prioritize and escalate cases, add private notes, publish support articles, and monitor service analytics.

## Compliance and regulatory management

Environmental officers and administrators can manage regulatory bodies, licences, recycler certifications, environmental certificates, submissions, checklist requirements, inspections and reports, violations, corrective actions, penalties, and document-expiry alerts. The module calculates a transparent compliance score and generates audit-ready PDF reports.

## Recycling partner and vendor management

Environmental officers and administrators can register external recyclers, repair centres, material buyers, transporters, disposal facilities, and other service partners. The partner workspace manages licence verification, services and coverage areas, contracts, pricing, capacity, payment terms, compliance records, document-expiry alerts, suspension, performance ratings, SLA compliance, spend, and printable partner reports.

## Marketplace and circular economy

Authenticated users can register buyer profiles, search resale-approved refurbished devices and sales-ready recovered materials, request quotations, place orders, submit payment-provider references, follow delivery events, cancel eligible orders, print digital receipts, and review sellers. Repair and recycling roles can create seller profiles and listings, verify payments, dispatch orders, update delivery tracking, and monitor marketplace analytics. No card or bank credentials are stored.

## Donation and social impact management

Donation workflows cover beneficiary registration and eligibility, requests, approval, allocation of donation-approved refurbished devices, delivery scheduling and proof, beneficiary confirmation, usage follow-up, social-impact history, certificates, and impact reporting.

## Rewards and incentives management

Green rewards include immutable point history, pickup and referral references, recycling challenges, user levels, leaderboards, coupon and partner rewards, redemption, one-year expiry metadata, duplicate-reference fraud prevention, business sustainability scores, and digital environmental certificates.

## Payment and billing management

The centralized financial ledger supports pickup-fee calculation, taxes and service charges, invoices, tokenized mobile-money/card intents, bank references, confirmations, failures and retries, refunds, partner and collector payouts, transaction history, status tracking, reconciliation snapshots, and PDF invoices. Sensitive card, PIN, and bank credentials are never stored.

## Analytics and reporting management

Environmental officers and administrators can filter operational KPIs by date, analyse collections, categories, regions, pickups, centres, recycling, recovery, revenue, users, partners and environmental performance, compose report datasets, schedule report definitions, and export PDF or Excel-compatible CSV files across operational, academic, financial, regulatory and incident report categories.

## Notification and communication management

Users receive in-app operational messages and manage channel/type preferences. Administrators can queue templated push, SMS, email, emergency, pickup, assignment, payment, reward, compliance and maintenance communications through a provider-ready outbox without embedding delivery-provider secrets in the app.

## Incident, safety and document management

Operational teams can report accidents, injuries, hazardous exposure, equipment damage and risks with locations, staff, evidence and immediate response. Governance staff manage investigations, root cause, corrective actions, follow-up, closure, statistics and emergency contacts. The secure document vault adds categories, versions, approval, expiry alerts, owner/governance access, download, archive and immutable audit trails.

## Background route tracking

Active driver routes support Android and iOS background location with staged permission requests, a prominent disclosure, visible platform indicators, and pause/complete controls. Store-console and privacy work that cannot be completed in source code is listed in [the release checklist](docs/background-location-release-checklist.md).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
