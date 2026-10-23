# MinIO recovery images for Production Cloud Platform

## Purpose

These unofficial container images package the recovered upstream MinIO
Server and MinIO Client binaries required by the Loki Helm deployment in
the Production Cloud Platform disaster-recovery environment.

They are compatibility artifacts for this project, not official MinIO images.

## Recovered components

|      Component       |            Version           |             Upstream commit              |
|         ---          |              ---             |                    ---                   |
| MinIO Server         | RELEASE.2024-12-18T13-15-44Z | 16f8cf1c52f0a77eeb8f7565aaf7f7df12454583 |
| MinIO Client (`mc`)  | RELEASE.2024-11-21T17-21-54Z | 1681e4497c09d7438a34e846f76dbde972ab7daf |

Upstream repositories:

- https://github.com/minio/minio
- https://github.com/minio/mc

The versions above were read from the recovered binaries.
The binaries were copied from an existing MinIO pod and packaged into
custom containers. Their byte-for-byte identity with upstream release
artifacts has not yet been independently verified.

## Container packaging

- `Dockerfile.minio` packages the MinIO Server binary, the recovered
  container entrypoint, and a CA certificate bundle.
- `Dockerfile.mc` packages the MinIO Client binary and a CA certificate
  bundle.
- Both Dockerfiles use BusyBox as their base image.
- No application-level modifications were made to the recovered MinIO
  Server or Client binaries.

The container packaging is unofficial and is not affiliated with or
endorsed by MinIO, Inc.

## Image references

- `ghcr.io/av-crypto-security/minio-recovery:RELEASE.2024-12-18T13-15-44Z`
- `ghcr.io/av-crypto-security/mc-recovery:RELEASE.2024-11-21T17-21-54Z`

These references are intended publication names. Do not consider the
images publicly available until publication and anonymous pull access
have been verified.

## Checksums

`checksums.sha256` records SHA-256 checksums for the recovered binaries
and packaging files from the recovery workstation.

The binary checksums identify the recovered files; they do not by
themselves prove upstream provenance.

## Licensing and source availability

The MinIO Server and MinIO Client binaries report GNU AGPL version 3.
The full AGPLv3 text is included as `LICENSE-AGPL-3.0.txt`.

- AGPLv3: https://www.gnu.org/licenses/agpl-3.0.html
- MinIO Server source: https://github.com/minio/minio
- MinIO Client source: https://github.com/minio/mc
- BusyBox source and licensing: https://busybox.net/

The container also includes BusyBox, a CA certificate bundle, and
packaging scripts. Their applicable licences and source-availability
requirements must be considered separately before distributing the
images. See the upstream projects for the corresponding source code
and licence information.

These legacy versions do not receive ongoing security updates through
this recovery packaging. Use them only where the pinned versions are
needed for this project's recovery workflow; review and update the
components before using them in another environment.
