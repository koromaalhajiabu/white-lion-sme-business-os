# Standards Evidence Register

**Product:** White Lion SME Business Operating System  
**Repository:** `koromaalhajiabu/white-lion-sme-business-os`  
**Register version:** 1.0  
**Created:** 2026-11-12  
**Register owner:** White Lion Tech Solutions  
**Assessment type:** Internal evidence register; not a certification or independent audit.

## 1. Purpose and evidence rules

This register records verification evidence for product quality, security, business-data isolation, offline operation, accounting controls, deployment and recovery. It supports a structured review against relevant frameworks; it does not itself demonstrate compliance or certification.

Use these status values consistently:

- **PASS — retained evidence:** A reproducible result or artifact is available and referenced.
- **DEVELOPER-ATTESTED:** The developer reports that the test passed, but the underlying test record, screenshot, or log has not been attached here.
- **IMPLEMENTED / NOT TESTED:** The feature or control is present in the repository or database, but a successful end-to-end test has not been evidenced.
- **OPEN:** Evidence is missing, a test is outstanding, or a defect remains unresolved.
- **NOT APPLICABLE:** The control does not apply; record the reason.

Do not change a status to PASS merely because code or a database object exists. Record the environment, exact release, test date, tester, steps, expected and actual results, and evidence location for each new test. Redact passwords, access tokens, personal data and production secrets from all evidence.

## 2. Existing evidence snapshot

The entries below preserve previously reported results. Where an exact date, test run, screenshot, or tested release was not supplied, that gap is stated rather than guessed.

| ID | Area / test | Framework relevance | Current status | Existing evidence / limitation |
|---|---|---|---|---|
| EV-001 | Overall functional testing across the application | ISO/IEC 25010:2023 quality characteristics | DEVELOPER-ATTESTED | Developer reports having independently checked every aspect and that it works. Detailed test cases, date, environment and supporting artifacts have not yet been attached to this register. |
| EV-002 | Business data isolation between businesses | OWASP ASVS access control; ISO/IEC 27001 access-control practices | DEVELOPER-ATTESTED | Developer previously reported that business data isolation was tested successfully. Retain the test accounts, business IDs (redacted where needed), steps and results to make this independently reproducible. |
| EV-003 | Offline transaction sync | ISO/IEC 25010 reliability; data integrity practices | DEVELOPER-ATTESTED | Developer reported creating offline test transactions and successfully syncing them. Relevant workflow includes `sync_local_records`, `sync_local_transaction` and offline sync receipt/transaction tables. Detailed run evidence was not attached here. |
| EV-004 | Migration 045 accounting objects installed | Accounting controls; change and data-integrity practices | DEVELOPER-ATTESTED | Supabase SQL results previously showed the migration marker and the expected accounting reversal, period-close, backfill, opening-balance and guard objects. This verifies object presence, not a complete accounting outcome. |
| EV-005 | Four automatic accounting triggers enabled | Accounting automation and completeness | DEVELOPER-ATTESTED | Supabase SQL output previously confirmed triggers for offline sales, offline purchases, expenses and offline sale returns. No live transactions were available at the time, so posting and reconciliation behavior was not end-to-end tested. |
| EV-006 | JavaScript syntax validation | ISO/IEC 25010 maintainability / reliability | PASS — retained evidence | GitHub Actions run for commit `c52a62409b2e4b92a9d0fd69bae5ac646b206f23`: [Syntax validation run](https://github.com/koromaalhajiabu/white-lion-sme-business-os/actions/runs/43229338092). |
| EV-007 | GitHub Pages deployment | ISO/IEC 25010 reliability / deployability | PASS — retained evidence | GitHub Actions run for commit `c52a62409b2e4b92a9d0fd69bae5ac646b206f23`: [Pages deployment run](https://github.com/koromaalhajiabu/white-lion-sme-business-os/actions/runs/43229336400). |
| EV-008 | Browser interaction smoke test | ISO/IEC 25010 functional suitability | PASS — retained evidence | Earlier CI run for commit `8b828b62425fd91b70e28ff9c5feb083a8cc8354`: [Browser smoke test run](https://github.com/koromaalhajiabu/white-lion-sme-business-os/actions/runs/43226796275). This is a smoke test, not proof of every workflow. |
| EV-009 | Android APK build | ISO/IEC 25010 compatibility / portability | PASS — retained evidence | Earlier CI run for commit `8b828b62425fd91b70e28ff9c5feb083a8cc8354`: [Android build run](https://github.com/koromaalhajiabu/white-lion-sme-business-os/actions/runs/43226796134). A successful build does not by itself prove installation and runtime behavior on every Android device. |
| EV-010 | Backup restoration | Availability, recoverability and continuity | OPEN | Repository workflow documents encrypted logical backups and retention. A successful restore into a separate test project has not yet been evidenced. |
| EV-011 | Independent application security assessment | OWASP ASVS; ISO/IEC 27001 security assurance | OPEN | No independent penetration-test report or completed ASVS verification record is currently referenced by this register. |
| EV-012 | IFRS for SMEs accounting treatment review | IFRS for SMEs (Third Edition, 2025) | OPEN | Accounting code and ledger controls exist, but no qualified accountant's review/sign-off of the accounting mappings and financial statements has been recorded. Confirm Sierra Leone's applicable adoption and statutory requirements separately. |

## 3. Standards and framework mapping

This is a review map, not a claim that the product is certified or fully conforms.

| Framework | Relevant areas to map | Evidence to retain |
|---|---|---|
| ISO/IEC 25010:2023 | Functional suitability, performance efficiency, compatibility, interaction capability, reliability, security, maintainability, flexibility and safety | Test plans and results, supported-device matrix, performance observations, defect/retest history, deployment and recovery results |
| OWASP ASVS 5.0.0 | Authentication, session management, access control, input validation, cryptography, error handling, data protection, API and configuration security | Versioned ASVS checklist, source/configuration review, negative authorization tests, dependency and security scan outputs, independent test report |
| ISO/IEC 27001:2022 including applicable amendment | Organisational information-security management, risk treatment, access governance, incident handling, supplier and backup processes | Policies, risk register, asset/data inventory, access reviews, incident process, backup/restore records and internal audit evidence. Product code alone cannot establish an organisation's ISMS certification. |
| IFRS for SMEs, Third Edition (2025) | Recognition, measurement, presentation, disclosures and transition requirements applicable to the entity | Accountant-reviewed accounting policy, account mapping, representative transactions, trial balance, statements, reconciliations and disclosure checklist |
| Backup and recovery good practice | Backup completeness, confidentiality, retention, restore integrity and recovery objectives | Backup job logs, integrity checks, restore exercise, recovery time and recovery point measurements |

## 4. Evidence capture template

Copy this block for each new test. Use one record per test scenario.

### Test record

- **Evidence ID:**
- **Feature / control:**
- **Framework and clause/control reference:**
- **Environment:** (local / GitHub Pages / Supabase test / production)
- **Application release / commit SHA:**
- **Database migration version (if relevant):**
- **Test date and time (UTC):**
- **Tester / reviewer:**
- **Preconditions and test data:**
- **Steps performed:**
  1.
  2.
  3.
- **Expected result:**
- **Actual result:**
- **Status:** (PASS / DEVELOPER-ATTESTED / IMPLEMENTED / NOT TESTED / OPEN / NOT APPLICABLE)
- **Evidence link or artifact path:**
- **Defect / issue reference:**
- **Retest date and result:**
- **Reviewer notes:**

## 5. Priority evidence still to collect

1. Convert the developer-attested tests into dated records with screenshots, sanitized logs or reproducible steps.
2. Complete an OWASP ASVS 5.0.0 mapping, beginning with authentication, authorization, business/branch isolation, session handling, input validation, secrets and database/API access.
3. Run a backup restore exercise in a separate Supabase test project; record what was restored, what was excluded, and measured recovery time.
4. Exercise accounting workflows using clearly identified test transactions in a non-production business; reconcile journals, inventory valuation, COGS, returns, expenses and period close. Do not create artificial opening balances or alter live business records to manufacture evidence.
5. Obtain qualified accountant review of IFRS for SMEs mappings and applicable Sierra Leone statutory requirements.
6. Track findings with severity, owner, target date, remediation commit and retest evidence.

## 6. Scope and claims

This register is an internal engineering evidence record. It is not an ISO certificate, an OWASP verification certificate, a penetration-test report, a statutory audit, an independent accountant's opinion, or a guarantee of regulatory compliance.

Approved description while assurance work remains in progress:

> White Lion SME Business Operating System is developed with reference to recognised software quality, application security and accounting frameworks. Its reported functional tests and available repository evidence are being documented through an ongoing internal assurance process. No formal certification or independent compliance assessment is claimed.

**Change control:** Update this register when evidence is added, tests are repeated, controls change, or a new release materially affects a recorded result. Preserve prior results and identify the release to which each result applies.
