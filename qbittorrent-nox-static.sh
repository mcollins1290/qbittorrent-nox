#! /usr/bin/env bash
set -a
#######################################################################################################################################################
# Unset some variables to set defaults.
#######################################################################################################################################################
unset qb_skip_delete qb_git_proxy qb_curl_proxy qb_install_dir qb_build_dir qb_working_dir qb_modules_test qb_python_version qb_patches_url
#######################################################################################################################################################
# Define color values.
#######################################################################################################################################################
cr="\e[31m" && clr="\e[91m" # [c]olor[r]ed     && [c]olor[l]ight[r]ed
cg="\e[32m" && clg="\e[92m" # [c]olor[g]reen   && [c]olor[l]ight[g]reen
cy="\e[33m" && cly="\e[93m" # [c]olor[y]ellow  && [c]olor[l]ight[y]ellow
cb="\e[34m" && clb="\e[94m" # [c]olor[b]lue    && [c]olor[l]ight[b]lue
cm="\e[35m" && clm="\e[95m" # [c]olor[m]agenta && [c]olor[l]ight[m]agenta
cc="\e[36m" && clc="\e[96m" # [c]olor[c]yan    && [c]olor[l]ight[c]yan
#
tb="\e[1m" && td="\e[2m" && tu="\e[4m" && tn="\n" # [t]ext[b]old && [t]ext[d]im && [t]ext[u]nderlined && [t]ext[n]ewline
#
cdef="\e[39m" # [c]olor[def]ault
cend="\e[0m"  # [c]olor[end]
#######################################################################################################################################################
# This function sets some default values we use but whose values can be overridden by certain flags
#######################################################################################################################################################
set_default_values() {
	#
	libtorrent_version="${libtorrent_version:-2.0}"
	#
	qt_target_version='6'
	#
	qb_python_version="3"
	#
	standard="17" && cpp_standard="c${standard}" && cxx_standard="c++${standard}"
	#
	qb_modules=("all" "linux_headers" "glibc" "zlib" "iconv" "icu" "openssl" "boost" "libtorrent" "double_conversion" "qtbase" "qttools" "qbittorrent")
	#
	delete=()
	#
	qb_required_pkgs=("build-essential" "bison" "curl" "pkg-config" "automake" "libtool" "git" "perl" "python${qb_python_version}" "python${qb_python_version}-dev" "python${qb_python_version}-numpy")
	#
	qb_working_dir="$(printf "%s" "$(pwd <(dirname "${0}"))")"
	qb_working_dir_short="${qb_working_dir/$HOME/\~}"
	#
	qb_install_dir="${qb_working_dir}/qb-build"
	qb_install_dir_short="${qb_install_dir/$HOME/\~}"
}
#######################################################################################################################################################
# Check for required packages
#######################################################################################################################################################
check_dependencies() {
	echo -e "${tn}${tb}Checking if required core dependencies are installed${cend}${tn}"
	#
	for pkg in "${qb_required_pkgs[@]}"; do
		#
		pkgman() { dpkg -s "${pkg}"; }
		#
		if pkgman > /dev/null 2>&1; then
			echo -e " Dependency - ${cg}OK${cend} - ${pkg}"
		else
			if [[ -n "${pkg}" ]]; then
				deps_installed='no'
				echo -e " Dependency - ${cr}NO${cend} - ${pkg}"
				qb_checked_required_pkgs+=("$pkg")
			fi
		fi
	done
	#
	if [[ "${deps_installed}" = 'no' ]]; then # Check if user is able to install the dependencies, if yes then do so, if no then exit.
		if [[ "$(id -un)" = 'root' ]]; then
			echo -e "${tn}${cg}Updating${cend}${tn}"
			#
			apt-get update -y
			apt-get upgrade -y
			apt-get autoremove -y
			#
			[[ -f /var/run/reboot-required ]] && {
				echo -e "${tn}${cr}This machine requires a reboot to continue installation. Please reboot now.${cend}${tn}"
				exit
			}
			#
			echo -e "${tn}${cg}Installing required dependencies${cend}${tn}"
			#
			if ! apt-get install -y "${qb_checked_required_pkgs[@]}"; then
				echo
				exit
			fi
			#
			echo -e "${tn}${cg}Dependencies installed!${cend}"
			#
			deps_installed='yes'
		else
			echo -e "${tn}${tb}Please request or install the missing core dependencies before using this script${cend}"
			#
			echo -e "${tn}apk add ${qb_checked_required_pkgs[*]}${tn}"
			#
			exit
		fi
	fi
	#
	## All pkgs checks passed
	if [[ "${deps_installed}" != 'no' ]]; then
		echo -e "${tn}${tb}All checks - ${cg}OK${cend}${tb} - core dependencies are installed, continuing to build${cend}"
	fi
}
#######################################################################################################################################################
while (("${#}")); do
	case "${1}" in
		-b | --build-directory)
			qb_build_dir="${2}"
			shift 2
			;;
		--) # end argument parsing
			shift
			break
			;;
		*) # preserve positional arguments
			params1+=("${1}")
			shift
			;;
	esac
done
#
eval set -- "${params1[@]}" # Set positional arguments in their proper place.
#######################################################################################################################################################
# 2:  curl test download functions - default is no proxy - curl is a test function and curl_curl is the command function
#######################################################################################################################################################
curl_curl() {
		"$(type -P curl)" -sNL4fq --connect-timeout 5 --retry 5 --retry-delay 5 --retry-max-time 25 "${@}"
}
#
curl() {
	if ! curl_curl "${@}"; then
		echo 'error_url'
	fi
}
#######################################################################################################################################################
# 3: git test download functions - default is no proxy - git is a test function and git_git is the command function
#######################################################################################################################################################
git_git() {
	"$(type -P git)" "${@}"
}

git() {
	if [[ "${2}" = '-t' ]]; then
		url_test="${1}"
		tag_flag="${2}"
		tag_test="${3}"
	else
		url_test="${11}" # 11th place in our download folder function
	fi
	#
	if ! curl -I "${url_test%\.git}" &> /dev/null; then
		echo
		echo -e " ${cy}There is an issue with your proxy settings or network connection${cend}"
		echo
		exit
	fi
	#
	status="$(
		git_git ls-remote --exit-code "${url_test}" "${tag_flag}" "${tag_test}" &> /dev/null
		echo "${?}"
	)"
	#
	if [[ "${tag_flag}" = '-t' && "${status}" = '0' ]]; then
		echo "${tag_test}"
	elif [[ "${tag_flag}" = '-t' && "${status}" -ge '1' ]]; then
		echo 'error_tag'
	else
		if ! git_git "${@}"; then
			echo
			echo -e " ${cy}There is an issue with your proxy settings or network connection${cend}"
			echo
			exit
		fi
	fi
}

test_git_ouput() {
	if [[ "${1}" = 'error_tag' ]]; then
		echo -e "${tn} ${cy}Sorry, the provided ${3} tag ${cr}$2${cend}${cy} is not valid${cend}"
	fi
}
#######################################################################################################################################################
# Set Build Directory
#######################################################################################################################################################
set_build_directory() {
	if [[ -n "${qb_build_dir}" ]]; then
		if [[ "${qb_build_dir}" =~ ^/ ]]; then
			qb_install_dir="${qb_build_dir}"
			qb_install_dir_short="${qb_install_dir/$HOME/\~}"
		else
			qb_install_dir="${qb_working_dir}/${qb_build_dir}"
			qb_install_dir_short="${qb_working_dir_short}/${qb_build_dir}"
		fi
	fi
	#
	## Set lib and include directory paths based on install path.
	include_dir="${qb_install_dir}/include"
	lib_dir="${qb_install_dir}/lib"
	#
	## Define some build specific variables
	PATH="${qb_install_dir}/bin:${HOME}/bin${PATH:+:${PATH}}"
	LD_LIBRARY_PATH="-L${lib_dir}"
	PKG_CONFIG_PATH="-L${lib_dir}/pkgconfig"
	#
	## Define aux directory
	AUX_DIR="${PWD}/aux"
	# Compiler prefix
	COMPILER_PREFIX="arm-linux-gnueabihf"
}
#######################################################################################################################################################
# Set Compiler Flags
#######################################################################################################################################################
custom_flags_set() {
	CHOST="${COMPILER_PREFIX}"
	CC="${COMPILER_PREFIX}-gcc"
	CXX="${COMPILER_PREFIX}-g++"

	CXXFLAGS="-std=${cxx_standard} --static -static -w -mcpu=cortex-a72 -mtune=cortex-a72 -mfpu=neon-fp-armv8 -mfloat-abi=hard -I${include_dir}"
	CPPFLAGS="--static -static -w -mcpu=cortex-a72 -mtune=cortex-a72 -mfpu=neon-fp-armv8 -mfloat-abi=hard -I${include_dir}"
	LDFLAGS="--static -static -Wl,--no-as-needed -L${lib_dir} -lpthread -pthread"
}
custom_flags_reset() {
	CHOST="${COMPILER_PREFIX}"
        CC="${COMPILER_PREFIX}-gcc"
        CXX="${COMPILER_PREFIX}-g++"

        CXXFLAGS="-w -std=${cxx_standard}"
        CPPFLAGS="-w"
        LDFLAGS=""
}
custom_flags_unset() {
        unset CHOST
        unset CC
        unset CXX

        unset CXXFLAGS
        unset CPPFLAGS
        unset LDFLAGS
}
#######################################################################################################################################################
# Module URLs
#######################################################################################################################################################
set_module_urls() {
	#
	linux_headers_github_url="https://github.com/raspberrypi/linux"
	linux_headers_github_tag="$(git_git ls-remote --symref ${linux_headers_github_url} HEAD | awk -F'[/\t]' 'NR == 1 {print $3}')"
	#
	glibc_url="https://ftp.gnu.org/gnu/libc/glibc-2.31.tar.gz"
	#
	zlib_github_tag="$(git_git ls-remote -q -t --refs https://github.com/madler/zlib.git | awk '{sub("refs/tags/", "");sub("(.*)(-[^0-9].*)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)"
	zlib_url="https://github.com/madler/zlib/archive/${zlib_github_tag}.tar.gz"
	#
	iconv_url="https://ftp.gnu.org/gnu/libiconv/$(grep -Eo 'libiconv-([0-9]{1,3}[.]?)([0-9]{1,3}[.]?)([0-9]{1,3}?)\.tar.gz' <(curl https://ftp.gnu.org/gnu/libiconv/) | sort -V | tail -1)"
	#
	icu_github_tag="$(git_git ls-remote -q -t --refs https://github.com/unicode-org/icu.git | awk '/\/release-/{sub("refs/tags/release-", "");sub("(.*)(-[^0-9].*)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)"
	icu_url="https://github.com/unicode-org/icu/releases/download/release-${icu_github_tag}/icu4c-${icu_github_tag/-/_}-src.tgz"
	#
	openssl_github_tag="$(git_git ls-remote -q -t --refs https://github.com/openssl/openssl.git | awk '/openssl/{sub("refs/tags/", "");sub("(.*)(v6|rc|alpha|beta)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n1)"
	openssl_version="${openssl_github_tag#openssl-}"
	openssl_url="https://github.com/openssl/openssl/archive/${openssl_github_tag}.tar.gz"
	#
	boost_version="${boost_version:-$(git_git ls-remote -q -t --refs https://github.com/boostorg/boost.git | awk '{sub("refs/tags/boost-", "");sub("(.*)(rc|alpha|beta)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n1)}"
	boost_github_tag="boost-${boost_version}"
	boost_url="https://boostorg.jfrog.io/artifactory/main/release/${boost_version}/source/boost_${boost_version//./_}.tar.gz"
	boost_url_status="$(curl_curl -so /dev/null --head --write-out '%{http_code}' "https://boostorg.jfrog.io/artifactory/main/release/${boost_version}/source/boost_${boost_version//./_}.tar.gz")"
	boost_github_url="https://github.com/boostorg/boost.git"
	#
	qt_github_tag_list="$(git_git ls-remote -q -t --refs https://github.com/qt/qtbase.git | awk '/v/{sub("refs/tags/", "");sub("(.*)(-a|-b|-r)", ""); print $2 }' | awk '!/^$/' | sort -rV)"
	qt_version="$(grep -Em1 "v${qt_target_version}" <<< "${qt_github_tag_list}" | sed 's/-lts-lgpl//g')"
	read -ra qt_version_short_array <<< "${qt_version//\./ }"
	qt_version_short="${qt_version_short_array[0]/v/}.${qt_version_short_array[1]/v/}"
	qtbase_github_tag="${qt_version}"
	qttools_github_tag="${qt_version}"
	qtbase_url="https://download.qt.io/official_releases/qt/${qt_version_short}/${qtbase_github_tag/v/}/submodules/qtbase-everywhere-src-${qtbase_github_tag/v/}.tar.xz"
	qttools_url="https://download.qt.io/official_releases/qt/${qt_version_short}/${qttools_github_tag/v/}/submodules/qttools-everywhere-src-${qttools_github_tag/v/}.tar.xz"
	#
	qttools_github_tag="$(grep -Eom1 "v${qt_version}.([0-9]{1,2})" <<< "${qt_github_tag_list}")"
	qttools_github_url="https://github.com/qt/qttools.git"
	#
	libtorrent_github_url="https://github.com/arvidn/libtorrent.git"
	libtorrent_github_tags_list="$(git_git ls-remote -q -t --refs https://github.com/arvidn/libtorrent.git | awk '/\/v/{sub("refs/tags/", "");sub("(.*)(-[^0-9].*)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV)"
	libtorrent_github_tag_default="$(grep -Eom1 "v${libtorrent_version}.([0-9]{1,2})" <<< "${libtorrent_github_tags_list}")"
	libtorrent_github_tag="${libtorrent_github_tag:-$libtorrent_github_tag_default}"
	#
	qbittorrent_github_url="https://github.com/qbittorrent/qBittorrent.git"
	qbittorrent_github_tag_default="$(git_git ls-remote -q -t --refs https://github.com/qbittorrent/qBittorrent.git | awk '{sub("refs/tags/", "");sub("(.*)(-[^0-9].*|rc|alpha|beta)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n1)"
	qbittorrent_github_tag="${qbitorrent_github_tag:-$qbittorrent_github_tag_default}"
	#
	double_conversion_github_tag="$(git_git ls-remote -q -t --refs https://github.com/google/double-conversion.git | awk '/v/{sub("refs/tags/", "");sub("(.*)(v6|rc|alpha|beta)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n1)"
	double_conversion_version="${double_conversion_github_tag}"
	double_conversion_github_url="https://github.com/google/double-conversion.git"
	#
}
#######################################################################################################################################################
# Process requested modules passed in, create folders and set core variables
#######################################################################################################################################################
installation_modules() {
	params_count="${#}"
	params_test=1
	#
	for target in "${delete[@]}"; do
		for i in "${!qb_modules[@]}"; do
			if [[ "${qb_modules[i]}" = "${target}" ]]; then
				unset 'qb_modules[i]'
			fi
		done
	done
	#
	while [[ "${params_test}" -le "${params_count}" && "${params_count}" -gt '1' ]]; do
		if [[ "${qb_modules[*]}" =~ ${*:$params_test:1} ]]; then
			:
		else
			qb_modules_test="fail"
		fi
		params_test="$((params_test + 1))"
	done
	#
	if [[ "${params_count}" -le '1' ]]; then
		if [[ "${qb_modules[*]}" =~ ${*:$params_test:1} && -n "${*:$params_test:1}" ]]; then
			:
		else
			qb_modules_test="fail"
		fi
	fi
	#
	if [[ "${qb_modules_test}" != 'fail' ]]; then
		if [[ "${*}" =~ ([[:space:]]|^)"all"([[:space:]]|$) ]]; then
			for module in "${qb_modules[@]}"; do
				eval "skip_${module}=no"
			done
		else
			for module in "${@}"; do
				eval "skip_${module}=no"
			done
		fi
		#
		## Create directories.
		mkdir -p "${qb_install_dir}/logs"
		mkdir -p "${qb_install_dir}/completed"
		#
		## Set python variables.
		python_major="$(python"${qb_python_version}" -c "import sys; print(sys.version_info[0])")"
		python_minor="$(python"${qb_python_version}" -c "import sys; print(sys.version_info[1])")"
		python_micro="$(python"${qb_python_version}" -c "import sys; print(sys.version_info[2])")"
		#
		python_short_version="${python_major}.${python_minor}"
		python_link_version="${python_major}${python_minor}"
		#
		## Echo the build directory.
		echo -e "${tn}${tb}Install Prefix${cend} : ${clc}${qb_install_dir_short}${cend}"
		#
		## Some basic help
		echo -e "${tn}${tb}Script help${cend} : ${clc}${qb_working_dir_short}/$(basename -- "$0")${cend} ${clb}-h${cend}"
	else
		echo -e "${tn} ${cr}One or more of the provided modules are not supported${cend}"
		echo -e "${tn}${tb}This is a list of supported modules${cend}"
		echo -e "${tn} ${clm}${qb_modules[*]}${tn}${cend}"
		exit
	fi
}
#######################################################################################################################################################
# This function is to test a directory exists before attemtping to cd and fail with and exit code if it doesn't.
#######################################################################################################################################################
_cd() {
	if ! cd "${1}" > /dev/null 2>&1; then
		echo -e "This directory does not exist. There is a problem"
		echo
		echo -e "${clr}${1}${cend}"
		echo
		exit 1
	fi
}
#######################################################################################################################################################
# This function is for downloading source code
#######################################################################################################################################################
download_file() {
	if [[ -n "${1}" ]]; then
		url_filename="${2}"
		[[ -n "${3}" ]] && subdir="/${3}" || subdir=""
		echo -e "${tn}${cg}Installing $1${cend}${tn}"
		file_name="${qb_install_dir}/${1}.tar.gz"
		[[ -f "${file_name}" ]] && rm -rf {"${qb_install_dir:?}/$(tar tf "${file_name}" | grep -Eom1 "(.*)[^/]")","${file_name}"}
		curl "${url_filename}" -o "${file_name}"
		_cmd tar xf "${file_name}" -C "${qb_install_dir}"
		app_dir="${qb_install_dir}/$(tar tf "${file_name}" | head -1 | cut -f1 -d"/")${subdir}"
		mkdir -p "${app_dir}"
		[[ "${1}" != 'boost' ]] && _cd "${app_dir}"
	else
		echo
		echo "You must provide a filename name for the function - download_file"
		echo "It creates the name from the appname_github_tag variable set in the URL section"
		echo
		echo "download_file filename url"
		echo
		exit
	fi
}
#######################################################################################################################################################
# This function is for downloading git releases based on their tag.
#######################################################################################################################################################
download_folder() {
	if [[ -n "${1}" ]]; then
		github_tag="${1}_github_tag"
		url_github="${2}"
		[[ -n "${3}" ]] && subdir="/${3}" || subdir=""
		echo -e "${tn}${cg}Installing ${1}${cend}${tn}"
		folder_name="${qb_install_dir}/${1}"
		folder_inc="${qb_install_dir}/include/${1}"
		[[ -d "${folder_name}" ]] && rm -rf "${folder_name}"
		[[ "${1}" == 'libtorrent' && -d "${folder_inc}" ]] && rm -rf "${folder_inc}"
		_cmd git clone --no-tags --single-branch --branch "${!github_tag}" --shallow-submodules --recurse-submodules -j"$(nproc)" --depth 1 "${url_github}" "${folder_name}"
		mkdir -p "${folder_name}${subdir}"
		[[ -d "${folder_name}${subdir}" ]] && _cd "${folder_name}${subdir}"
	else
		echo
		echo "You must provide a tag name for the function - download_folder"
		echo "It creates the tag from the appname_github_tag variable set in the URL section"
		echo
		echo "download_folder tagname url subdir"
		echo
		exit
	fi
}
#######################################################################################################################################################
# This function is for removing files and folders we no longer need
#######################################################################################################################################################
delete_function() {
	if [[ -n "${1}" ]]; then
		if [[ -z "${qb_skip_delete}" ]]; then
			[[ "$2" = 'last' ]] && echo -e "${tn}${clr}Deleting $1 installation files and folders${cend}${tn}" || echo -e "${tn}${clr}Deleting ${1} installation files and folders${cend}"
			#
			file_name="${qb_install_dir}/${1}.tar.gz"
			folder_name="${qb_install_dir}/${1}"
			[[ -f "${file_name}" ]] && rm -rf {"${qb_install_dir:?}/$(tar tf "${file_name}" | grep -Eom1 "(.*)[^/]")","${file_name}"}
			[[ -d "${folder_name}" ]] && rm -rf "${folder_name}"
			[[ -d "${qb_working_dir}" ]] && _cd "${qb_working_dir}"
		else
			[[ "${2}" = 'last' ]] && echo -e "${tn}${clr}Skipping $1 deletion${cend}${tn}" || echo -e "${tn}${clr}Skipping ${1} deletion${cend}"
		fi
	else
		echo
		echo "The delete_function works in tandem with the application_name function"
		echo "Set the appname using the application_name function then use this function."
		echo
		echo "delete_function appname"
		echo
		exit
	fi
}
#######################################################################################################################################################
# This function sets the name of the application to be used with the functions download_file/folder and delete_function
#######################################################################################################################################################
application_name() {
	last_app_name="skip_${app_name}"
	app_name="${1}"
	app_name_skip="skip_${app_name}"
	app_url="${app_name}_url"
	app_github_url="${app_name}_github_url"
}
#######################################################################################################################################################
# This function skips the deletion of the -n flag is supplied
#######################################################################################################################################################
application_skip() {
	if [[ "${1}" = 'last' ]]; then
		echo -e "${tn}Skipping ${clm}$app_name${cend} module installation${tn}"
	else
		echo -e "${tn}Skipping ${clm}$app_name${cend} module installation"
	fi
}
#######################################################################################################################################################
# Generic exception handler for when commands are run within these script
#######################################################################################################################################################
_cmd() {
	if ! "${@}"; then
		echo
		exit 1
	fi
}
#######################################################################################################################################################
# Check build exit code
#######################################################################################################################################################
post_build() {
	outcome="${PIPESTATUS[0]}"
	if [[ ${outcome} -gt '0' ]]; then
		echo -e "${tn}${clr} Error: build command produced an exit code greater than 0 - Check the logs${cend}${tn}"
		exit "${outcome}"
	fi
}
#######################################################################################################################################################
# static lib link fix: check for *.so and *.a versions of a lib in the $lib_dir and change the *.so link to point to the static lib e.g. libdl.a
#######################################################################################################################################################
_fix_static_links() {
	log_name="$1"
	mapfile -t library_list < <(find "${lib_dir}" -maxdepth 1 -exec bash -c 'basename "$0" ".${0##*.}"' {} \; | sort | uniq -d)
	for file in "${library_list[@]}"; do
		if [[ "$(readlink "${lib_dir}/${file}.so")" != "${file}.a" ]]; then
			ln -fsn "${file}.a" "${lib_dir}/${file}.so"
			echo "${lib_dir}${file}.so changed to point to ${file}.a" >> "${qb_install_dir}/logs/${log_name}-fix-static-links.log.txt"
		fi
	done
	return
}
#######################################################################################################################################################
# error functions
#######################################################################################################################################################
_error_tag() {
	[[ "${qbittorrent_github_tag}" = "error_tag" ]] && {
		echo
		exit
	}
}
#######################################################################################################################################################
# Functions part 1: Use some of our functions
#######################################################################################################################################################
set_default_values "${@}"
#
check_dependencies
#
set_build_directory
#
set_module_urls

#######################################################################################################################################################
# Process flags passed into script.
#######################################################################################################################################################
while (("${#}")); do
	case "${1}" in
		-qm | --qbittorrent-master)
			qbittorrent_github_tag="$(git "${qbittorrent_github_url}" -t "master")"
			test_git_ouput "${qbittorrent_github_tag}" "master" "qbittorrent"
			shift
			;;
		-qt | --qbittorrent-tag)
			qbittorrent_github_tag="$(git "${qbittorrent_github_url}" -t "$2")"
			test_git_ouput "${qbittorrent_github_tag}" "$2" "qbittorrent"
			shift 2
			;;
		h-qm | --help-qbittorrent-master)
			echo
			echo -e " ${tb}${tu}Here is the help description for this flag:${cend}"
			echo
			echo -e " Always use the master branch for ${cg}qBittorrent${cend}"
			echo
			echo -e " This master that will be used is: ${cg}master${cend}"
			echo
			echo -e " ${td}This flag is provided with no arguments.${cend}"
			echo
			echo -e " ${clb}-qm${cend}"
			echo
			exit
			;;
		-h-qt | --help-qbittorrent-tag)
			echo
			echo -e " ${tb}${tu}Here is the help description for this flag:${cend}"
			echo
			echo -e " Use a provided qBittorrent tag when cloning from github."
			echo
			echo -e " ${cy}You can use this flag with this help command to see the value if called before the help option.${cend}"
			echo
			echo -e " ${cg}${qb_working_dir_short}/$(basename -- "$0")${cend}${clb} -qt ${clc}${qbittorrent_github_tag}${cend} ${clb}-h-qt${cend}"
			#
			if [[ ! "${qbittorrent_github_tag}" =~ (error_tag|error_22) ]]; then
				echo
				echo -e " ${td}This tag that will be used is: ${cg}${qbittorrent_github_tag}${cend}"
			fi
			echo
			echo -e " ${td}This flag must be provided with arguments.${cend}"
			echo
			echo -e " ${clb}-qt${cend} ${clc}${qbittorrent_github_tag}${cend}"
			echo
			exit
			;;
		--) # end argument parsing
			shift
			break
			;;
		-*) # unsupported flags
			echo -e "${tn}Error: Unsupported flag ${cr}$1${cend} - use ${cg}-h${cend} or ${cg}--help${cend} to see the valid options${tn}" >&2
			exit 1
			;;
		*) # preserve positional arguments
			params2+=("${1}")
			shift
			;;
	esac
done
#
eval set -- "${params2[@]}" # Set positional arguments in their proper place.

############################################################################################################$
# Lets check github tags to see if they are valid
############################################################################################################$
_error_tag

#### Output qBittorrent and Library versions and have user confirm
openssl_pretty_version="${openssl_github_tag#OpenSSL_}" && openssl_pretty_version="${openssl_pretty_version//_/.}"

printf "qBittorrent ${qbittorrent_github_tag#release-} will be built with the following libraries:\n"
printf "\n"
printf "Qt: ${qt_version#v}\n"
printf "Libtorrent: ${libtorrent_github_tag#v}\n"
printf "Boost: ${boost_version#v}\n"
printf "OpenSSL: ${openssl_pretty_version}\n"
printf "zlib: ${zlib_github_tag#v}\n"
printf "\n"

read -r -p "Would you like to continue with the build? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
	:
else
	echo "Exiting..."
	exit 0
fi
####

echo "Continue..."
s_timestamp=$(date +'%s')
#######################################################################################################################################################
# Functions part 3: Use some of our functions
#######################################################################################################################################################
installation_modules "${@}"
#######################################################################################################################################################
# linux_headers installation
#######################################################################################################################################################
application_name linux_headers
#
if [[ "${!app_name_skip:-yes}" = 'no' || "${1}" = "${app_name}" ]]; then
        custom_flags_unset
	#
	download_folder "${app_name}" "${!app_github_url}"
        #
        make headers_install INSTALL_HDR_PATH="${qb_install_dir}" |& tee "${qb_install_dir}/logs/${app_name}.log.txt"
        #
        post_build
        #
        delete_function "${app_name}"
else
        application_skip
fi
#######################################################################################################################################################
# glibc installation
#######################################################################################################################################################
application_name glibc

if [[ "${!app_name_skip:-yes}" == 'no' || "${1}" == "${app_name}" ]]; then
	#
	if [[ ! -d "${qb_install_dir}/include" ]]; then
        	echo -e "${tn}${clr} Warning${cend} This module depends on the linux_headers module. Use them together: ${clm}linux_headers glibc${cend}"
        	echo
	else
		custom_flags_reset
		download_file "${app_name}" "${!app_url}"
		#
		mkdir -p build
		_cd "${app_dir}/build"
		#
		"${app_dir}/configure" --host="${COMPILER_PREFIX}" --prefix="${qb_install_dir}" --enable-static-nss --disable-nscd |& tee "${qb_install_dir}/logs/${app_name}.log.txt"
		make -j"$(nproc)" |& tee -a "${qb_install_dir}/logs/$app_name.log.txt"
		#
		post_build
		#
		make install |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
		#
		_fix_static_links "${app_name}"
		#
		delete_function "${app_name}"
	fi
else
	application_skip
fi
#######################################################################################################################################################
# zlib installation
#######################################################################################################################################################
application_name zlib
#
if [[ "${!app_name_skip:-yes}" = 'no' || "${1}" = "${app_name}" ]]; then
	custom_flags_set
	download_file "${app_name}" "${!app_url}"
	#
	./configure --prefix="${qb_install_dir}" --static |& tee "${qb_install_dir}/logs/${app_name}.log.txt"
	make -j"$(nproc)" CXXFLAGS="${CXXFLAGS}" CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}" |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
	#
	post_build
	#
	make install |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
	#
	_fix_static_links "${app_name}"
	#
	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# iconv installation
#######################################################################################################################################################
application_name iconv

if [[ "${!app_name_skip:-yes}" == 'no' || "${1}" == "${app_name}" ]]; then
	custom_flags_reset
	download_file "${app_name}" "${!app_url}"
	#
	./configure --host="${COMPILER_PREFIX}" --prefix="${qb_install_dir}" --disable-shared --enable-static CXXFLAGS="${CXXFLAGS}" CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}" |& tee "${qb_install_dir}/logs/${app_name}.log.txt"
	#
	make -j"$(nproc)" |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
	#
	make install |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
	#
	_fix_static_links "${app_name}"
	#
	post_build
	#
	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# ICU installation
#######################################################################################################################################################
application_name icu

if [[ "${!app_name_skip:-yes}" == 'no' || "${1}" == "${app_name}" ]]; then
	custom_flags_reset
	#
	download_file "${app_name}" "${!app_url}" "/source"
	#
	mkdir -p "${qb_install_dir}/${app_name}/cross"
	_cd "${qb_install_dir}/${app_name}/cross"
	"${qb_install_dir}/${app_name}/source/runConfigureICU" Linux/gcc
	make -j"$(nproc)"
	_cd "${qb_install_dir}/${app_name}/source"
	#
	./configure --host="${COMPILER_PREFIX}" -with-cross-build="${qb_install_dir}/icu/cross" --prefix="${qb_install_dir}" --disable-shared --enable-static --disable-samples --disable-tests --with-data-packaging=static CXXFLAGS="${CXXFLAGS}" CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}" |& tee "${qb_install_dir}/logs/${app_name}.log.txt"
	#
	make -j"$(nproc)" |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
	#
	post_build
	#
	make install |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
	#
	_fix_static_links "${app_name}"
	#
	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# openssl installation
#######################################################################################################################################################
application_name openssl
#
if [[ "${!app_name_skip:-yes}" = 'no' || "${1}" = "${app_name}" ]]; then
	custom_flags_set
	download_file "${app_name}" "${!app_url}"
	#
	./Configure linux-generic32 --prefix="${qb_install_dir}" --openssldir="/etc/ssl" threads no-shared no-dso no-comp CXXFLAGS="${CXXFLAGS}" CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}" |& tee "${qb_install_dir}/logs/${app_name}.log.txt"
	make -j"$(nproc)" |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
	#
	post_build
	#
	make install_sw |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
	#
	_fix_static_links "${app_name}"
	#
	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# boost libraries install
#######################################################################################################################################################
application_name boost
#
if [[ "${!app_name_skip:-yes}" = 'no' ]] || [[ "${1}" = "${app_name}" ]]; then
	custom_flags_set
	#
	[[ -d "${qb_install_dir}/boost" ]] && delete_function "${app_name}"
	#
	if [[ "${boost_url_status}" =~ (200) ]]; then
		download_file "${app_name}" "${boost_url}"
		rm -rf "${qb_install_dir}/boost.tar.gz"
		mv -f "${qb_install_dir}/boost_${boost_version//./_}/" "${qb_install_dir}/boost"
		_cd "${qb_install_dir}/boost"
	fi
	#
	if [[ "${boost_url_status}" =~ (403|404) ]]; then
		download_folder "${app_name}" "${!app_github_url}"
	fi
	#
	"${qb_install_dir}/boost/bootstrap.sh"|& tee "${qb_install_dir}/logs/${app_name}.log.txt"
	#
	if [[ "${boost_url_status}" =~ (403|404) ]]; then
		"${qb_install_dir}/boost/b2" headers |& tee "${qb_install_dir}/logs/${app_name}.log.txt"
	fi
else
	application_skip
fi
#######################################################################################################################################################
# libtorrent installation
#######################################################################################################################################################
application_name libtorrent

if [[ "${!app_name_skip:-yes}" == 'no' ]] || [[ "${1}" == "${app_name}" ]]; then
	if [[ ! -d "${qb_install_dir}/boost" ]]; then
		echo -e "${tn} ${urc}${clr} Warning${cend} This module depends on the boost module. Use them together: ${clm}boost libtorrent${cend}"
	else
		custom_flags_set
		#
		download_folder "${app_name}" "${!app_github_url}"
		#
		BOOST_ROOT="${qb_install_dir}/boost"
		BOOST_INCLUDEDIR="${qb_install_dir}/boost"
		BOOST_BUILD_PATH="${qb_install_dir}/boost"
		#
		cmake -Wno-dev -Wno-deprecated -G Ninja -B build \
			-D CMAKE_CXX_COMPILER="${COMPILER_PREFIX}-g++" \
			-D CMAKE_VERBOSE_MAKEFILE=OFF \
			-D CMAKE_BUILD_TYPE="Release" \
			-D CMAKE_CXX_STANDARD="${standard}" \
			-D CMAKE_PREFIX_PATH="${qb_install_dir};${qb_install_dir}/boost" \
			-D Boost_NO_BOOST_CMAKE=TRUE \
			-D CMAKE_CXX_FLAGS="${CXXFLAGS}" \
			-D BUILD_SHARED_LIBS=OFF \
			-D Iconv_LIBRARY="${lib_dir}/libiconv.a" \
			-D CMAKE_INSTALL_PREFIX="${qb_install_dir}" |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
		cmake --build build |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
		#
		post_build
		#
		cmake --install build |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
		#
		_fix_static_links "${app_name}"
		#
		delete_function "${app_name}"
	fi
else
	application_skip
fi
#######################################################################################################################################################
# double conversion installation
#######################################################################################################################################################
application_name double_conversion

if [[ "${!app_name_skip:-yes}" == 'no' || "${1}" == "${app_name}" ]]; then
	custom_flags_set
	#
	download_folder "${app_name}" "${!app_github_url}"
	#
	cmake -Wno-dev -Wno-deprecated -G Ninja -B build \
		-D CMAKE_CXX_COMPILER="${COMPILER_PREFIX}-g++" \
		-D CMAKE_VERBOSE_MAKEFILE=OFF \
		-D CMAKE_PREFIX_PATH="${qb_install_dir}" \
		-D CMAKE_CXX_FLAGS="${CXXFLAGS}" \
		-D CMAKE_INSTALL_LIBDIR=lib \
		-D BUILD_SHARED_LIBS=OFF \
		-D CMAKE_INSTALL_PREFIX="${qb_install_dir}" |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
	#
	cmake --build build |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
	#
	cmake --install build |& tee -a "${qt_install_dir}/logs/${app_name}.log.txt"
	#
	post_build
	#
	_fix_static_links "${app_name}"
	#
	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# qtbase installation
#######################################################################################################################################################
application_name qtbase

if [[ "${!app_name_skip:-yes}" == 'no' ]] || [[ "${1}" == "${app_name}" ]]; then
	#
	download_file "${app_name}" "${!app_url}"
	#
	if [[ ! -d "${qb_install_dir}/qt-host" ]]; then
		#
		# BUILD QT BASE FOR HOST
		#
		echo -e "${tn}${clc}Building Qt Base for Host${cend}"
		custom_flags_unset
		#
		cmake -Wno-dev -Wno-deprecated -G Ninja -B build-host \
			-D CMAKE_VERBOSE_MAKEFILE=OFF \
			-D CMAKE_BUILD_TYPE="release" \
			-D QT_FEATURE_optimize_full=on \
			-D QT_FEATURE_gui=off \
			-D QT_FEATURE_widgets=off \
			-D QT_FEATURE_testlib=off \
			-D QT_BUILD_EXAMPLES=off \
			-D QT_BUILD_TESTS=off \
			-D CMAKE_CXX_STANDARD="${standard}" \
			-D CMAKE_INSTALL_PREFIX="${qb_install_dir}/qt-host" |& tee -a "${qb_install_dir}/logs/${app_name}-HOST.log.txt"
		cmake --build build-host |& tee -a "${qb_install_dir}/logs/${app_name}-HOST.log.txt"
		#
		post_build
		#
		cmake --install build-host |& tee -a "${qb_install_dir}/logs/${app_name}-HOST.log.txt"
	fi
	#
	# BUILD QT BASE FOR RPI
	#
	echo -e "${tn}${clc}Building Qt Base for RPi${cend}"
	custom_flags_set
	#
	./configure -static -- -Wno-dev -Wno-deprecated -G Ninja -B build-rpi \
		-D CMAKE_BUILD_TYPE="release" \
		-D CMAKE_VERBOSE_MAKEFILE=OFF \
		-D QT_HOST_PATH="${qb_install_dir}/qt-host" \
		-D CMAKE_TOOLCHAIN_FILE="${AUX_DIR}/toolchain.cmake" \
		-D QT_FEATURE_optimize_full=on -D QT_FEATURE_static=on -D QT_FEATURE_shared=off \
		-D QT_FEATURE_gui=off -D QT_FEATURE_openssl_linked=on \
		-D QT_FEATURE_dbus=off -D QT_FEATURE_system_pcre2=off -D QT_FEATURE_widgets=off \
		-D QT_FEATURE_testlib=off -D QT_BUILD_EXAMPLES=off -D QT_BUILD_TESTS=off \
		-D QT_FEATURE_brotli=off \
		-D CMAKE_CXX_STANDARD="${standard}" \
		-D CMAKE_PREFIX_PATH="${qb_install_dir}" \
		-D CMAKE_INSTALL_PREFIX="${qb_install_dir}" \
		-D CMAKE_FIND_ROOT_PATH="${qb_install_dir}" \
		-D QT_BUILD_SHARED_LIBS=off \
		-D CMAKE_SKIP_RPATH=on -D CMAKE_SKIP_INSTALL_RPATH=on \
		-D QT_QMAKE_TARGET_MKSPEC=devices/linux-rasp-pi4-v3d-g++ |& tee -a "${qb_install_dir}/logs/${app_name}-RPI.log.txt"
	#
	cmake --build build-rpi |& tee -a "${qb_install_dir}/logs/${app_name}-RPI.log.txt"
	#
	post_build
	#
	cmake --install build-rpi |& tee -a "${qb_install_dir}/logs/${app_name}-RPI.log.txt"
	#
	_fix_static_links "${app_name}"
	#
	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# qttools installation
#######################################################################################################################################################
application_name qttools
#
if [[ "${!app_name_skip:-yes}" == 'no' ]] || [[ "${1}" == "${app_name}" ]]; then
	if [[ ! -d "${qb_install_dir}/qt-host" ]]; then
		echo -e "${tn} ${urc}${clr} Warning${cend} This module depends on the qtbase module. Use them together: ${clm}qtbase qttools${cend}"
	else
		#
		download_file "${app_name}" "${!app_url}"
		#
		# BUILD QT TOOLS FOR HOST
		#
		custom_flags_unset
		echo -e "${tn}${clc}Building Qt Tools for Host${cend}"
		"${qb_install_dir}/qt-host/bin/qt-cmake" -Wno-dev -Wno-deprecated -G Ninja -B build-host \
			-D CMAKE_VERBOSE_MAKEFILE=OFF \
			-D CMAKE_BUILD_TYPE="release" \
			-D CMAKE_CXX_STANDARD="${standard}" \
			-D CMAKE_PREFIX_PATH="${qb_install_dir}/qt-host" \
			-D CMAKE_INSTALL_PREFIX="${qb_install_dir}/qt-host" |& tee -a "${qb_install_dir}/logs/${app_name}-HOST.log.txt"
		cmake --build build-host |& tee -a "${qb_install_dir}/logs/${app_name}-HOST.log.txt"
		#
		post_build
		#
		cmake --install build-host |& tee -a "${qb_install_dir}/logs/${app_name}-HOST.log.txt"
		#
                # BUILD QT TOOLS FOR RPi
                #
		custom_flags_set
		echo -e "${tn}${clc}Building Qt Tools for RPi${cend}"
		"${qb_install_dir}/bin/qt-cmake" -Wno-dev -Wno-deprecated -G Ninja -B build-rpi \
			-D CMAKE_VERBOSE_MAKEFILE=OFF \
			-D CMAKE_BUILD_TYPE="release" \
			-D CMAKE_CXX_STANDARD="${standard}" \
			-D CMAKE_PREFIX_PATH="${qb_install_dir}" \
			-D CMAKE_CXX_FLAGS="${CXXFLAGS}" \
			-D BUILD_SHARED_LIBS=OFF \
			-D CMAKE_SKIP_RPATH=on -D CMAKE_SKIP_INSTALL_RPATH=on \
			-D CMAKE_INSTALL_PREFIX="${qb_install_dir}" |& tee -a "${qb_install_dir}/logs/${app_name}-RPi.log.txt"
		cmake --build build-rpi |& tee -a "${qb_install_dir}/logs/${app_name}-RPi.log.txt"
		#
		post_build
		#
		cmake --install build-rpi |& tee -a "${qb_install_dir}/logs/${app_name}-RPi.log.txt"
		#
		_fix_static_links "${app_name}"
		#
		delete_function "${app_name}"
	fi
else
	application_skip
fi
#######################################################################################################################################################
# qBittorrent installation
#######################################################################################################################################################
application_name qbittorrent

if [[ "${!app_name_skip:-yes}" == 'no' ]] || [[ "${1}" == "${app_name}" ]]; then
	if [[ ! -d "${qb_install_dir}/boost" ]]; then
		echo -e "${tn} ${urc}${clr} Warning${cend} This module depends on the boost module. Use them together: ${clm}boost qbittorrent${cend}"
		echo
	else
		custom_flags_set
		#
		download_folder "${app_name}" "${!app_github_url}"
		"${qb_install_dir}/bin/qt-cmake" -Wno-dev -Wno-deprecated -G Ninja -B build \
			-D CMAKE_VERBOSE_MAKEFILE=ON \
			-D CMAKE_BUILD_TYPE="release" \
			-D QT6=ON \
			-D CMAKE_CXX_STANDARD="${standard}" \
			-D CMAKE_PREFIX_PATH="${qb_install_dir};${qb_install_dir}/boost" \
			-D Boost_NO_BOOST_CMAKE=TRUE \
			-D CMAKE_CXX_FLAGS="${CXXFLAGS}" \
			-D GUI=OFF \
			-D CMAKE_INSTALL_PREFIX="${qb_install_dir}" |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
		cmake --build build |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
		#
		post_build
		#
		cmake --install build |& tee -a "${qb_install_dir}/logs/${app_name}.log.txt"
		#
		[[ -f "${qb_install_dir}/bin/qbittorrent-nox" ]] && cp -f "${qb_install_dir}/bin/qbittorrent-nox" "${qb_install_dir}/completed/qbittorrent-nox"
		[[ -f "${qb_install_dir}/completed/qbittorrent-nox" ]] && "${COMPILER_PREFIX}-strip" "${qb_install_dir}/completed/qbittorrent-nox"
		#
		application_name boost && delete_function boost
		application_name qbittorrent && delete_function "${app_name}" last
		#
		echo -e "${cg}Build completed successfully.${cend}"
	fi
else
	application_skip last
fi
#######################################################################################################################################################
# We are all done so output duration and exit
#######################################################################################################################################################
f_timestamp=$(date +'%s')
dur="$(($f_timestamp-$s_timestamp))"
h=$(( dur / 3600 ))
m=$(( ( dur / 60 ) % 60 ))
s=$(( dur % 60 ))
printf "Duration: %02d:%02d:%02d\n\n" $h $m $s

exit
