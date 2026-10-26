Hermes Company Certificate Installer
====================================

Usage:
1. Put these files in the same folder:
   - install_hermes_company_cert.py
   - my_company.crt

2. Run one of these:
   PowerShell:
     python .\install_hermes_company_cert.py

   CMD:
     python install_hermes_company_cert.py

   Or double-click:
     run_install_cert.bat

3. Close and reopen PowerShell/CMD after it finishes.

What it sets:
- SSL_CERT_FILE
- REQUESTS_CA_BUNDLE
- CURL_CA_BUNDLE
- NODE_EXTRA_CA_CERTS

The script expects my_company.crt to be PEM/Base64 and contain:
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
