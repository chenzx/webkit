# Copyright (c) 2009, Daniel Krech All rights reserved.
# Copyright (C) 2010 Chris Jerdonek (cjerdonek@webkit.org)
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#  * Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#
#  * Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
#  * Neither the name of the Daniel Krech nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

"""Support for automatically downloading Python packages from an URL."""

import logging
import new
import os
import shutil
import sys
import tarfile
import tempfile
import urllib
import urlparse
import zipfile
import zipimport

_log = logging.getLogger(__name__)


class AutoInstaller(object):

    """Supports automatically installing Python packages from an URL.

    Supports uncompressed files, .tar.gz, and .zip formats.

    Basic usage:

    installer = AutoInstaller()

    installer.install(url="http://pypi.python.org/packages/source/p/pep8/pep8-0.5.0.tar.gz#md5=512a818af9979290cd619cce8e9c2e2b",
                      url_subpath="pep8-0.5.0/pep8.py")
    installer.install(url="http://pypi.python.org/packages/source/m/mechanize/mechanize-0.1.11.zip",
                      url_subpath="mechanize")

    """

    def __init__(self, append_to_search_path=False, make_package=True,
                 target_dir=None, temp_dir=None):
        """Create an AutoInstaller instance, and set up the target directory.

        Args:
          append_to_search_path: A boolean value of whether to append the
                                 target directory to the sys.path search path.
          make_package: A boolean value of whether to make the target
                        directory a package.  This adds an __init__.py file
                        to the target directory -- allowing packages and
                        modules within the target directory to be imported
                        explicitly using dotted module names.
          target_dir: The directory path to which packages should be installed.
                      Defaults to a subdirectory of the folder containing
                      this module called "autoinstalled".
          temp_dir: The directory path to use for any temporary files
                    generated while downloading, unzipping, and extracting
                    packages to install.  Defaults to a standard temporary
                    location generated by the tempfile module.  This
                    parameter should normally be used only for development
                    testing.

        """
        if target_dir is None:
            this_dir = os.path.dirname(__file__)
            target_dir = os.path.join(this_dir, "autoinstalled")

        # Ensure that the target directory exists.
        self._set_up_target_dir(target_dir, append_to_search_path, make_package)

        self._target_dir = target_dir
        self._temp_dir = temp_dir

    def _log_transfer(self, message, source, target, log_method=None):
        """Log a debug message that involves a source and target."""
        if log_method is None:
            log_method = _log.debug

        log_method("%s" % message)
        log_method('    From: "%s"' % source)
        log_method('      To: "%s"' % target)

    def _create_directory(self, path, name=None):
        """Create a directory."""
        log = _log.debug

        name = name + " " if name is not None else ""
        log('Creating %sdirectory...' % name)
        log('    "%s"' % path)

        os.makedirs(path)

    def _write_file(self, path, text):
        """Create a file at the given path with given text.

        This method overwrites any existing file.

        """
        _log.debug("Creating file...")
        _log.debug('    "%s"' % path)
        file = open(path, "w")
        try:
            file.write(text)
        finally:
            file.close()

    def _set_up_target_dir(self, target_dir, append_to_search_path,
                           make_package):
        """Set up a target directory.

        Args:
          target_dir: The path to the target directory to set up.
          append_to_search_path: A boolean value of whether to append the
                                 target directory to the sys.path search path.
          make_package: A boolean value of whether to make the target
                        directory a package.  This adds an __init__.py file
                        to the target directory -- allowing packages and
                        modules within the target directory to be imported
                        explicitly using dotted module names.

        """
        if not os.path.exists(target_dir):
            self._create_directory(target_dir, "autoinstall target")

        if append_to_search_path:
            sys.path.append(target_dir)

        if make_package:
            init_path = os.path.join(target_dir, "__init__.py")
            if not os.path.exists(init_path):
                text = ("# This file is required for Python to search this "
                        "directory for modules.\n")
                self._write_file(init_path, text)

    def _create_scratch_directory_inner(self, prefix):
        """Create a scratch directory without exception handling.

        Creates a scratch directory inside the AutoInstaller temp
        directory self._temp_dir, or inside a platform-dependent temp
        directory if self._temp_dir is None.  Returns the path to the
        created scratch directory.

        Raises:
          OSError: [Errno 2] if the containing temp directory self._temp_dir
                             is not None and does not exist.

        """
        # The tempfile.mkdtemp() method function requires that the
        # directory corresponding to the "dir" parameter already exist
        # if it is not None.
        scratch_dir = tempfile.mkdtemp(prefix=prefix, dir=self._temp_dir)
        return scratch_dir

    def _create_scratch_directory(self, target_name):
        """Create a temporary scratch directory, and return its path.

        The scratch directory is generated inside the temp directory
        of this AutoInstaller instance.  This method also creates the
        temp directory if it does not already exist.

        """
        prefix = target_name + "_"
        try:
            scratch_dir = self._create_scratch_directory_inner(prefix)
        except OSError:
            # Handle case of containing temp directory not existing--
            # OSError: [Errno 2] No such file or directory:...
            temp_dir = self._temp_dir
            if temp_dir is None or os.path.exists(temp_dir):
                raise
            # Else try again after creating the temp directory.
            self._create_directory(temp_dir, "autoinstall temp")
            scratch_dir = self._create_scratch_directory_inner(prefix)

        return scratch_dir

    def _url_downloaded_path(self, target_name):
        """Return the path to the file containing the URL downloaded."""
        filename = ".%s.url" % target_name
        path = os.path.join(self._target_dir, filename)
        return path

    def _is_downloaded(self, target_name, url):
        """Return whether a package version has been downloaded."""
        version_path = self._url_downloaded_path(target_name)

        _log.debug('Checking %s URL downloaded...' % target_name)
        _log.debug('    "%s"' % version_path)

        if not os.path.exists(version_path):
            # Then no package version has been downloaded.
            _log.debug("No URL file found.")
            return False

        file = open(version_path, "r")
        try:
            version = file.read()
        finally:
            file.close()

        return version.strip() == url.strip()

    def _record_url_downloaded(self, target_name, url):
        """Record the URL downloaded to a file."""
        version_path = self._url_downloaded_path(target_name)
        _log.debug("Recording URL downloaded...")
        _log.debug('    URL: "%s"' % url)
        _log.debug('     To: "%s"' % version_path)

        self._write_file(version_path, url)

    def _extract_targz(self, path, scratch_dir):
        # tarfile.extractall() extracts to a path without the
        # trailing ".tar.gz".
        target_basename = os.path.basename(path[:-len(".tar.gz")])
        target_path = os.path.join(scratch_dir, target_basename)

        self._log_transfer("Starting gunzip/extract...", path, target_path)

        try:
            tar_file = tarfile.open(path)
        except tarfile.ReadError, err:
            # Append existing Error message to new Error.
            message = ("Could not open tar file: %s\n"
                       " The file probably does not have the correct format.\n"
                       " --> Inner message: %s"
                       % (path, err))
            raise Exception(message)

        try:
            # This is helpful for debugging purposes.
            _log.debug("Listing tar file contents...")
            for name in tar_file.getnames():
                _log.debug('    * "%s"' % name)
            _log.debug("Extracting gzipped tar file...")
            tar_file.extractall(target_path)
        finally:
            tar_file.close()

        return target_path

    # This is a replacement for ZipFile.extractall(), which is
    # available in Python 2.6 but not in earlier versions.
    def _extract_all(self, zip_file, target_dir):
        self._log_transfer("Extracting zip file...", zip_file, target_dir)

        # This is helpful for debugging purposes.
        _log.debug("Listing zip file contents...")
        for name in zip_file.namelist():
            _log.debug('    * "%s"' % name)

        for name in zip_file.namelist():
            path = os.path.join(target_dir, name)
            self._log_transfer("Extracting...", name, path)

            if not os.path.basename(path):
                # Then the path ends in a slash, so it is a directory.
                self._create_directory(path)
                continue
            # Otherwise, it is a file.

            try:
                outfile = open(path, 'wb')
            except IOError, err:
                # Not all zip files seem to list the directories explicitly,
                # so try again after creating the containing directory.
                _log.debug("Got IOError: retrying after creating directory...")
                dir = os.path.dirname(path)
                self._create_directory(dir)
                outfile = open(path, 'wb')

            try:
                outfile.write(zip_file.read(name))
            finally:
                outfile.close()

    def _unzip(self, path, scratch_dir):
        # zipfile.extractall() extracts to a path without the
        # trailing ".zip".
        target_basename = os.path.basename(path[:-len(".zip")])
        target_path = os.path.join(scratch_dir, target_basename)

        self._log_transfer("Starting unzip...", path, target_path)

        try:
            zip_file = zipfile.ZipFile(path, "r")
        except zipfile.BadZipfile, err:
            message = ("Could not open zip file: %s\n"
                       " --> Inner message: %s"
                       % (path, err))
            raise Exception(message)

        try:
            self._extract_all(zip_file, scratch_dir)
        finally:
            zip_file.close()

        return target_path

    def _prepare_package(self, path, scratch_dir):
        """Prepare a package for use, if necessary, and return the new path.

        For example, this method unzips zipped files and extracts
        tar files.

        Args:
          path: The path to the downloaded URL contents.
          scratch_dir: The scratch directory.  Note that the scratch
                       directory contains the file designated by the
                       path parameter.

        """
        # FIXME: Add other natural extensions.
        if path.endswith(".zip"):
            new_path = self._unzip(path, scratch_dir)
        elif path.endswith(".tar.gz"):
            new_path = self._extract_targz(path, scratch_dir)
        else:
            # No preparation is needed.
            new_path = path

        return new_path

    def _download_to_stream(self, url, stream):
        """Download an URL to a stream, and return the number of bytes."""
        try:
            netstream = urllib.urlopen(url)
        except IOError, err:
            # Append existing Error message to new Error.
            message = ('Could not download Python modules from URL "%s".\n'
                       " Make sure you are connected to the internet.\n"
                       " You must be connected to the internet when "
                       "downloading needed modules for the first time.\n"
                       " --> Inner message: %s"
                       % (url, err))
            raise IOError(message)
        code = 200
        if hasattr(netstream, "getcode"):
            code = netstream.getcode()
        if not 200 <= code < 300:
            raise ValueError("HTTP Error code %s" % code)

        BUFSIZE = 2**13  # 8KB
        bytes = 0
        while True:
            data = netstream.read(BUFSIZE)
            if not data:
                break
            stream.write(data)
            bytes += len(data)
        netstream.close()
        return bytes

    def _download(self, url, scratch_dir):
        """Download URL contents, and return the download path."""
        url_path = urlparse.urlsplit(url)[2]
        url_path = os.path.normpath(url_path)  # Removes trailing slash.
        target_filename = os.path.basename(url_path)
        target_path = os.path.join(scratch_dir, target_filename)

        self._log_transfer("Starting download...", url, target_path)

        stream = file(target_path, "wb")
        bytes = self._download_to_stream(url, stream)
        stream.close()

        _log.debug("Downloaded %s bytes." % bytes)

        return target_path

    def _install(self, scratch_dir, package_name, target_path, url,
                 url_subpath):
        """Install a python package from an URL.

        This internal method overwrites the target path if the target
        path already exists.

        """
        path = self._download(url=url, scratch_dir=scratch_dir)
        path = self._prepare_package(path, scratch_dir)

        if url_subpath is None:
            source_path = path
        else:
            source_path = os.path.join(path, url_subpath)

        if os.path.exists(target_path):
            _log.debug('Refreshing install: deleting "%s".' % target_path)
            if os.path.isdir(target_path):
                shutil.rmtree(target_path)
            else:
                os.remove(target_path)

        self._log_transfer("Moving files into place...", source_path, target_path)

        # The shutil.move() command creates intermediate directories if they
        # do not exist, but we do not rely on this behavior since we
        # need to create the __init__.py file anyway.
        shutil.move(source_path, target_path)

        self._record_url_downloaded(package_name, url)

    def install(self, url, should_refresh=False, target_name=None,
                url_subpath=None):
        """Install a python package from an URL.

        Args:
          url: The URL from which to download the package.

        Optional Args:
          should_refresh: A boolean value of whether the package should be
                          downloaded again if the package is already present.
          target_name: The name of the folder or file in the autoinstaller
                       target directory at which the package should be
                       installed.  Defaults to the base name of the
                       URL sub-path.  This parameter must be provided if
                       the URL sub-path is not specified.
          url_subpath: The relative path of the URL directory that should
                       be installed.  Defaults to the full directory, or
                       the entire URL contents.

        """
        if target_name is None:
            if not url_subpath:
                raise ValueError('The "target_name" parameter must be '
                                 'provided if the "url_subpath" parameter '
                                 "is not provided.")
            # Remove any trailing slashes.
            url_subpath = os.path.normpath(url_subpath)
            target_name = os.path.basename(url_subpath)

        target_path = os.path.join(self._target_dir, target_name)
        if not should_refresh and self._is_downloaded(target_name, url):
            _log.debug('URL for %s already downloaded.  Skipping...'
                       % target_name)
            _log.debug('    "%s"' % url)
            return

        self._log_transfer("Auto-installing package: %s" % target_name,
                            url, target_path, log_method=_log.info)

        # The scratch directory is where we will download and prepare
        # files specific to this install until they are ready to move
        # into place.
        scratch_dir = self._create_scratch_directory(target_name)

        try:
            self._install(package_name=target_name,
                          target_path=target_path,
                          scratch_dir=scratch_dir,
                          url=url,
                          url_subpath=url_subpath)
        except Exception, err:
            # Append existing Error message to new Error.
            message = ("Error auto-installing the %s package to:\n"
                       ' "%s"\n'
                       " --> Inner message: %s"
                       % (target_name, target_path, err))
            raise Exception(message)
        finally:
            _log.debug('Cleaning up: deleting "%s".' % scratch_dir)
            shutil.rmtree(scratch_dir)
        _log.debug('Auto-installed %s to:' % target_name)
        _log.debug('    "%s"' % target_path)


if __name__=="__main__":

    # Configure the autoinstall logger to log DEBUG messages for
    # development testing purposes.
    console = logging.StreamHandler()

    formatter = logging.Formatter('%(name)s: %(levelname)-8s %(message)s')
    console.setFormatter(formatter)
    _log.addHandler(console)
    _log.setLevel(logging.DEBUG)

    # Use a more visible temp directory for debug purposes.
    this_dir = os.path.dirname(__file__)
    target_dir = os.path.join(this_dir, "autoinstalled")
    temp_dir = os.path.join(target_dir, "Temp")

    installer = AutoInstaller(target_dir=target_dir,
                              temp_dir=temp_dir)

    installer.install(should_refresh=False,
                      target_name="pep8.py",
                      url="http://pypi.python.org/packages/source/p/pep8/pep8-0.5.0.tar.gz#md5=512a818af9979290cd619cce8e9c2e2b",
                      url_subpath="pep8-0.5.0/pep8.py")
    installer.install(should_refresh=False,
                      target_name="mechanize",
                      url="http://pypi.python.org/packages/source/m/mechanize/mechanize-0.1.11.zip",
                      url_subpath="mechanize")

