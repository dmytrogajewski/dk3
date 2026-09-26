%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none
%global _binary_payload w3.zstdio
Name: dk3
Version: 0.1.0
Release: 208%{?dist}
Summary: Daikatana development port with locally supplied game assets
License: GPL-2.0-or-later AND BSD-3-Clause AND Zlib AND IJG AND LicenseRef-Proprietary-Daikatana-Assets
URL: https://github.com/dmytrogajewski/dk3
Source0: payload.tar
ExclusiveArch: x86_64
Requires: python3
Requires: /usr/bin/prlimit
Requires: libcurl.so.4()(64bit)

%description
Independent native Daikatana development port using the bundled ioquake3 engine.
Includes locally supplied converted assets, HD textures, native modules, dkguard,
the online guest CLI and an explicitly trusted default Internet room service.
This private local package is not a completed game release. Game assets retain
 their original ownership and are not covered by the source-code GPL grant.
No player identities, saved games or server credentials are included.

%prep
%setup -q -c -T
 tar -xf %{SOURCE0}

%build
# Assemble already-built, manifest-verified native products. No private runtime
# or source outside the selected independent installation is imported.

%install
mkdir -p %{buildroot}
cp -a payload/. %{buildroot}/

%files
%{_bindir}/dk3
%{_bindir}/dk3-online
%{_libexecdir}/dk3/
%{_libdir}/dk3/
%{_datadir}/dk3/
%{_datadir}/applications/dk3.desktop
%license %{_datadir}/licenses/dk3/
%doc %{_docdir}/dk3/
