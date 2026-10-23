# Third-party notices — MinIO recovery images

These are unofficial compatibility images for this project's disaster-recovery
workflow. They are not official MinIO images and are not endorsed by MinIO, Inc.

## MinIO Server

- Reported version: RELEASE.2024-12-18T13-15-44Z
- Reported commit: 16f8cf1c52f0a77eeb8f7565aaf7f7df12454583
- Source: https://github.com/minio/minio
- License reported by the binary: GNU AGPL version 3
- License text: LICENSE-AGPL-3.0.txt

## MinIO Client (mc)

- Reported version: RELEASE.2024-11-21T17-21-54Z
- Reported commit: 1681e4497c09d7438a34e846f76dbde972ab7daf
- Source: https://github.com/minio/mc
- License reported by the binary: GNU AGPL version 3
- License text: LICENSE-AGPL-3.0.txt

The binaries were recovered from a running MinIO pod. Their byte-for-byte
identity with upstream release artifacts has not been independently verified.

## BusyBox base image

- Dockerfile base reference: busybox:1.36
- The recovered image history identified BusyBox 1.36.1 (glibc), but the
  original base image digest was not preserved.
- Project: https://busybox.net/
- Docker Official Image packaging: https://github.com/docker-library/busybox
- License: GNU GPL version 2; see LICENSE-BUSYBOX-GPL-2.0.txt

The BusyBox source and applicable corresponding-source obligations must be
considered when redistributing the built images. The upstream links above are
provided for source and licensing information; this notice is not a claim that
all redistribution obligations have been independently audited.

The recovery Dockerfiles use the `busybox:1.36` base image. During the 
recovery-image audit, Docker reported the base image digest as 
`sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662`, 
and the image history identified the build as BusyBox 1.36.1 (glibc), Debian 13.
The base image provides BusyBox applets and includes the associated runtime 
components, including glibc libraries and the dynamic loader. These are part 
of the base image, not separately installed packages in the recovery Dockerfiles.
The observed digest records the image retrieved during this audit; the original 
digest used by the recovered upstream workload was not preserved. 
The `busybox:1.36` tag in the Dockerfiles is not itself an immutable 
image reference.

## Entrypoint and CA bundle

docker-entrypoint.sh and ca-certificates.crt were copied from the working
MinIO pod used during recovery. The original package version and exact upstream
provenance of the CA bundle have not been independently established.

## Integrity and security

See checksums.sha256 for recorded recovery-file checksums. Checksums establish
file integrity against the recorded values, not upstream provenance.

These legacy components are pinned for recovery compatibility and do not
receive updates through this project. Do not reuse these images for new
deployments without reviewing their security, licensing, and provenance.
