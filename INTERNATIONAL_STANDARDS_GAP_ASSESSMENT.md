# White Lion SME Business OS — International Standards Readiness Assessment

**Assessment date:** 12 November 2026  
**Repository:** https://github.com/koromaalhajiabu/white-lion-sme-business-os  
**Live application:** https://koromaalhajiabu.github.io/white-lion-sme-business-os/  
**Assessment type:** Internal, repository-based gap assessment  
**Prepared for:** White Lion Tech Solutions

## 1. Executive conclusion

White Lion SME Business OS has a substantial multi-industry SME platform foundation. The repository contains a GitHub Pages PWA, Supabase authentication and tenant controls, offline transaction synchronisation, branch operations, inventory costing, accounting ledger workflows, audit logging and an encrypted logical backup workflow.

The developer has stated that they have independently tested every aspect of the live system and that it works. This assessment records that statement as **developer-attested functional testing**. This review did not independently log into the live Supabase project, inspect its private settings or repeat the developer's end-to-end tests.

**Conclusion:** The available evidence supports describing the product as *built with international-standard-aligned practices and independently function-tested by its developer*. It does not support claiming formal ISO certification, independently audited security, or accounting software compliance with IFRS for SMEs. No confirmed functional defect was identified in this documentation-focused review. The principal remaining gaps are standards mapping, retained test evidence, organisational controls and independent assurance.

Do not use “ISO certified”, “IFRS compliant”, “audited accounting software” or similar claims unless the relevant independent assessment has actually been completed.

## 2. Evidence reviewed

### Repository and release evidence

- README.md and its documented platform architecture and limitations.
- PROFESSIONAL_READINESS.md.
- BACKUP_GUIDE.md.
- supabase/PRODUCTION_SECURITY_AUDIT.sql.
- .github/workflows/supabase-backup.yml.
- Supabase migrations 018 (double-entry ledger), 019 (weighted-average inventory costing) and 045 (historical backfill, opening balances, journal reversals and period close).
- Latest repository commit reviewed: c52a62409b2e4b92a9d0fd69bae5ac646b206f23.
- GitHub Actions on that commit: JavaScript syntax validation **passed** and GitHub Pages deployment **passed** on 12 November 2026.
- Browser interaction smoke test and Android APK build had successful runs on an earlier 12 November commit (8b828b62425fd91b70e28ff9c5feb083a8cc8354). These are useful CI signals, not proof of every live workflow or real-device behaviour.

### Developer-attested evidence

The developer reports that all aspects of the live system have been independently tested and work. Previous Supabase results supplied by the developer also confirmed:
- Business data isolation was tested successfully.
- Migration 045's marker and its principal tables/functions/trigger were present.
- Four accounting triggers were enabled: offline sales, offline purchases, expenses and offline sale returns.
- At the time of the accounting checks, the business had no transactions, so there were no live transaction postings to reconcile.

These results are recorded as supplied test evidence, not as a fresh live database inspection performed during this assessment.

## 3. Standards and framework assessment

| Reference | What it evaluates | Current assessment | Remaining evidence / work |
|---|---|---|---|
| ISO/IEC 25010:2023 | Software product quality model | Strong feature and release-engineering foundation; developer-attested functional testing; current syntax and Pages deployment CI pass | Retain a requirements-to-test matrix for functional suitability, performance, compatibility, interaction capability, reliability, security, maintainability, flexibility and safety. Preserve browser/device test reports and measured performance/accessibility results. |
| OWASP ASVS 5.0.0 | Verifiable web application security requirements | A read-only Supabase SQL audit exists for RLS coverage, RLS tables without policies, anon/PUBLIC table grants and SECURITY DEFINER functions without pinned search_path | Complete a versioned ASVS control-by-control review. The current SQL audit is useful but does not cover every application, authentication, session, API, upload, browser, storage and deployment control. Record pass/fail/not-applicable with evidence. |
| ISO/IEC 27001:2022 + Amd 1:2024 | Organisation-wide information security management system | Technical security controls are represented in the application and database architecture; repository alone cannot establish an organisation-wide ISMS | Establish and retain scope, asset/risk register, risk-treatment plan, information-security policy, roles, supplier controls, incident response, access reviews, backup policy, internal audit and management review. Prepare a Statement of Applicability. Certification is optional and requires an accredited independent certification body. |
| IFRS for SMEs Accounting Standard, Third Edition (2025) | Recognition, measurement, presentation and disclosures in SME financial statements | Ledger, chart of accounts, balanced journals, inventory costing, financial report foundations, backfill, opening balances, reversals and period close are implemented in migrations | A qualified accountant must map every applicable Standard section to system behaviour and validate reports/disclosures using representative cases. The third edition is effective for periods beginning on or after 1 January 2027, with early application permitted. Confirm Sierra Leone adoption and applicable local tax/statutory rules. |
| Backup and operational resilience | Recoverability, continuity and data integrity | Encrypted scheduled logical JSON/Auth metadata/Storage/migrations backup workflow is present; retention is 30 days | Preserve successful run/artifact evidence and a signed restore-test report from a separate Supabase recovery project. Document recovery time and recovery point objectives. The workflow is not a full physical/custom-format PostgreSQL backup and omits some project-level settings and secrets. |

## 4. Specific findings and boundaries

### 4.1 Software quality

**Implemented evidence**
- Static PWA hosted through GitHub Pages.
- Responsive layout and service-worker/offline architecture.
- GitHub Actions for JavaScript syntax validation, browser smoke tests, Pages deployment and Android APK packaging.
- Multi-language support documented in README.

**Evidence still needed for a standards-grade quality claim**
- Measured performance under realistic data volume and network conditions.
- Accessibility evaluation, including keyboard navigation, contrast and screen-reader support.
- A documented browser/OS/device compatibility matrix.
- Defect tracking, severity classification and regression-test coverage.
- Maintainability and change-control evidence.

### 4.2 Application and database security

**Implemented evidence**
- Supabase authentication, business membership and row-level security are part of the architecture.
- A read-only security audit SQL script is present.
- The codebase documents that a service-role key must never be placed in browser code.
- Accounting period and journal controls use role checks and security-definer functions with a pinned search_path in migration 045.

**Remaining assurance**
- Save and review the actual output of PRODUCTION_SECURITY_AUDIT.sql against the intended public/private data model.
- Test both allowed and denied access for each role, including cross-business and cross-branch attempts.
- Review function EXECUTE grants, storage bucket policies, account recovery, session expiry, MFA policy, rate limits, CSP, CORS, file validation and secret rotation.
- Commission an independent penetration test before making a security assurance claim.

A clean result from the supplied SQL audit would be a useful control check, not proof of complete OWASP ASVS or ISO/IEC 27001 conformity.

### 4.3 Accounting and IFRS for SMEs

**Implemented evidence**
- Double-entry ledger and chart of accounts.
- Journal posting and financial report foundations.
- Weighted-average inventory valuation and COGS posting.
- Historical accounting backfill, opening balances, immutable reversals and period-close controls in migration 045.
- Automatic accounting triggers were reported enabled in the live Supabase project.

**Important boundaries**
- The repository's own readiness documentation says manual cashbook entries are not automatically journaled in this release.
- The README states that operating dashboard totals are not audited net profit or available cash.
- A functioning ledger is not, by itself, proof of IFRS for SMEs compliance. Presentation, disclosures, recognition/measurement policies, estimates, impairment, tax, leases, provisions, financial instruments, revenue and other applicable sections need professional mapping.
- The 2025 third edition becomes effective for annual reporting periods beginning on or after 1 January 2027; local adoption and early application need to be considered.

No accounting entries should be fabricated for testing. Where the live business has no transactions, use a dedicated test business or accountant-approved test dataset and retain the reconciliation evidence.

### 4.4 Backup and recovery

The current workflow:
- Runs on a schedule and can be manually triggered.
- Exports PostgREST-readable table data, Auth user metadata, private business-document objects and repository migrations.
- Encrypts the archive before artifact upload.
- Retains GitHub Actions artifacts for 30 days.

Documented limitations:
- It is a logical JSON backup, not a full physical/custom-format PostgreSQL dump.
- It does not export passwords, MFA secrets, active sessions, provider secrets or all Supabase project settings.
- Objects not represented in the repository migrations may need separate recreation.
- A successful backup job does not prove that restoration works.

The acceptance evidence required is a successful restore into a separate recovery project, followed by verification of login, business membership, RLS, accounting, inventory, branch records and private document downloads. If the developer has already completed this test, retain its date, recovery-project identifier (without publishing secrets), run ID and outcome in the evidence register.

### 4.5 Commercial and jurisdictional readiness

The repository documents manual subscription payment submission and administrator verification. Direct Orange Money/AfriMoney/bank API checkout and automated recurring collection are not implemented as provider integrations. This is a product-scope limitation, not necessarily a defect in the core SME operating system.

Before statutory or commercial deployment, obtain local advice on Sierra Leone tax, invoicing, record retention, privacy and any applicable electronic transaction requirements. International standards do not replace local law.

## 5. Priority action register

| Priority | Action | Completion evidence |
|---|---|---|
| P1 | Create a retained test-evidence register for the developer's completed end-to-end tests | Dated test cases, expected/actual results, screenshots or logs, tester and release commit |
| P1 | Complete OWASP ASVS 5.0.0 control mapping and independent security review | Control matrix, findings, remediation record and retest |
| P1 | Complete an accountant-led IFRS for SMEs section mapping | Signed accounting policy/report mapping and reconciled sample financial statements |
| P1 | Perform or document a separate-project backup restoration | Restore run ID, restore date, integrity checks and recovery validation |
| P2 | Establish ISO/IEC 27001-aligned organisational ISMS documentation | Scope, risk register, treatment plan, policies, SoA, audit and management-review records |
| P2 | Produce ISO/IEC 25010 quality evidence | Performance, accessibility, compatibility, reliability and maintainability test reports |
| P2 | Confirm local Sierra Leone statutory and tax requirements | Written advice or documented sign-off from an appropriately qualified local professional |

## 6. Evidence register template

For each test, retain:
- Test ID and standards/control reference.
- Feature and environment tested.
- Build commit or deployed release.
- Preconditions and test data (no real secrets).
- Steps performed.
- Expected and actual result.
- Pass/fail/not applicable.
- Date, tester and reviewer.
- Screenshot, log, query output or report reference.
- Defect/ticket and retest reference, if applicable.

## 7. Approved external wording

Recommended product statement:

> “White Lion SME Business OS is a multi-industry SME operations platform developed by White Lion Tech Solutions. It incorporates security, software-quality and accounting design practices informed by recognised international frameworks. Its functionality has been independently tested by its developer. Formal certification and independent conformity assessments are separate activities and are not claimed.”

Do not use ISO logos or claim certification without a valid certificate and permission from the relevant certification body.

## 8. Reference standards

- ISO/IEC 27001:2022 — Information security management systems requirements: https://www.iso.org/standard/27001
- ISO/IEC 25010:2023 — Software product quality model: https://webstore.iec.ch/en/publication/90024
- OWASP Application Security Verification Standard 5.0.0: https://asvs.owasp.org/
- IFRS Foundation — IFRS for SMEs 2025 supporting materials and third edition: https://www.ifrs.org/supporting-implementation/2025-ifrs-for-smes-supporting-materials/

---

**Assessment status:** Internal gap assessment completed from repository evidence and developer-attested testing. Not a certification, statutory audit, penetration-test report or independent accounting opinion.
