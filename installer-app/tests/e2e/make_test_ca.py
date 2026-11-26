"""Creates a throw-away test CA ("company root") and a localhost server certificate signed by it.

usage: make_test_ca.py <out-dir>
writes: <out-dir>/ca.crt (DER, like a file downloaded from an internal site), server.pem, server.key
Only for the e2e test; nothing here is a real certificate."""
import datetime
import ipaddress
import os
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
now = datetime.datetime.now(datetime.timezone.utc)

ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ca_name = x509.Name([x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Ornek Sirket"),
                     x509.NameAttribute(NameOID.COMMON_NAME, "Ornek Sirket Test Kok CA")])
ca = (x509.CertificateBuilder().subject_name(ca_name).issuer_name(ca_name).public_key(ca_key.public_key())
      .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(days=1))
      .not_valid_after(now + datetime.timedelta(days=30 * 12))
      .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
      .add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False, key_encipherment=False,
                                   data_encipherment=False, key_agreement=False, key_cert_sign=True, crl_sign=True,
                                   encipher_only=False, decipher_only=False), critical=True)
      .add_extension(x509.SubjectKeyIdentifier.from_public_key(ca_key.public_key()), critical=False)
      .sign(ca_key, hashes.SHA256()))

srv_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
srv = (x509.CertificateBuilder()
       .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "localhost")]))
       .issuer_name(ca_name).public_key(srv_key.public_key()).serial_number(x509.random_serial_number())
       .not_valid_before(now - datetime.timedelta(days=1)).not_valid_after(now + datetime.timedelta(days=90))
       .add_extension(x509.SubjectAlternativeName([x509.DNSName("localhost"),
                                                   x509.IPAddress(ipaddress.ip_address("127.0.0.1"))]), critical=False)
       .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
       .add_extension(x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
       .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()), critical=False)
       .sign(ca_key, hashes.SHA256()))

with open(os.path.join(out, "ca.crt"), "wb") as f:
    f.write(ca.public_bytes(serialization.Encoding.DER))
with open(os.path.join(out, "server.pem"), "wb") as f:
    f.write(srv.public_bytes(serialization.Encoding.PEM))
with open(os.path.join(out, "server.key"), "wb") as f:
    f.write(srv_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
                                  serialization.NoEncryption()))
print("CA thumbprint (SHA1):", ca.fingerprint(hashes.SHA1()).hex().upper())
