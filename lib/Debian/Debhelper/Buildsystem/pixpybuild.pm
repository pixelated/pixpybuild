package Debian::Debhelper::Buildsystem::pixpybuild;

use strict;
use warnings;

use Debian::Debhelper::Dh_Lib qw(error doit escape_shell clean_jobserver_makeflags);
use File::Spec;
use File::Slurp qw(edit_file read_dir);
use base 'Debian::Debhelper::Buildsystem';
# use base 'Debian::Debhelper::Buildsystem::python_distutils';

use Cwd qw(abs_path);

sub DESCRIPTION {
        "Python pixpybuild"
}

sub DEFAULT_BUILD_DIRECTORY {
	my $this=shift;
	return $this->canonpath($this->get_sourcepath("build"));
}

sub exists_make_target {
        my ($this, $target) = @_;

        # Use make -n to check to see if the target would do
        # anything. There's no good way to test if a target exists.
        my @opts=("-s", "-n", "--no-print-directory");
        #my $buildpath = $this->get_buildpath();
        my $sourcepath = $this->get_sourcepath();
        unshift @opts, "-C", $sourcepath if $sourcepath ne ".";
        open(SAVEDERR, ">&STDERR");
        open(STDERR, ">/dev/null");
        open(MAKE, "-|", $this->{makecmd}, @opts, $target);
        my $output=<MAKE>;
        chomp $output;
        close MAKE;
        open(STDERR, ">&SAVEDERR");
        return defined $output && length $output;
}

sub do_make {
        my $this=shift;

        # Avoid possible warnings about unavailable jobserver,
        # and force make to start a new jobserver.
        clean_jobserver_makeflags();

        # Note that this will override any -j settings in MAKEFLAGS.
        unshift @_, "-j" . ($this->get_parallel() > 0 ? $this->get_parallel() : "");

	unshift @_, "-C", abs_path($this->get_sourcepath());

        $this->doit_in_builddir($this->{makecmd}, @_);
}

sub make_first_existing_target {
        my $this=shift;
        my $targets=shift;

        foreach my $target (@$targets) {
                if ($this->exists_make_target($target)) {
                        $this->do_make($target, @_);
                        return $target;
                }
        }
        return undef;
}

sub check_auto_buildable {
        my $this=shift;

	warning("warning: pixpybuild.pm#check_auto_buildable called");

        return -e $this->get_sourcepath("setup.py") ? 3 : 0;
}

sub new {
	my $class=shift;
	my $this=$class->SUPER::new(@_);

	$this->prefer_out_of_source_building();
	$this->{makecmd} = (exists $ENV{MAKE}) ? $ENV{MAKE} : "make";
	return $this;
}

sub get_install_root {
    my $prefix = "/usr/share/python";
    if (defined $ENV{DH_VIRTUALENV_INSTALL_ROOT}) {
        $prefix = $ENV{DH_VIRTUALENV_INSTALL_ROOT};
    }
    return $prefix;
}

sub get_venv_builddir {
	my $this=shift;
	my $builddir = $this->get_builddir();
	my $sourcepackage = $this->sourcepackage();
	my $prefix = $this->get_install_root();

	return "$builddir$prefix/$sourcepackage";
}

sub get_exec {
    my $this = shift;
    my $executable = shift;
    my $builddir = $this->get_venv_builddir();
    return abs_path("$builddir/bin/$executable");
}

sub get_python {
    my $this = shift;
    return $this->get_exec("python");
}

sub get_pip {
    my $this = shift;
    return $this->get_exec("pip");
}

sub configure {
	my $this=shift;
	doit('mkdir', '-p', $this->get_venv_builddir());
}

sub build {
	my $this=shift;
	if (-e $this->get_sourcepath("setup.py")) {
		$this->build_python();
	} elsif (-e $this->get_sourcepath("Makefile")) {
		$this->build_makefile();
	}
}

sub build_python {
	my $this=shift;
	my $builddir = abs_path($this->get_builddir());
	my $venvdir = abs_path($this->get_venv_builddir());

	# create the virtual env
	doit('virtualenv', $venvdir);

	# only now we have access to python and pip
	my $python = $this->get_python();
	my $pip = $this->get_pip();

	# update pip and setuptools
	$this->doit_in_sourcedir($python, $pip, 'install', '--upgrade', 'pip');
	$this->doit_in_sourcedir($python, $pip, 'install', '--upgrade', 'setuptools');

	# install pip requirements if requirements.txt exists
	if (-e $this->get_sourcepath('requirements.txt')) {
		$this->doit_in_sourcedir($python, $pip, 'install', '--requirement', 'requirements.txt');
	}

	#$this->doit_in_sourcedir("${venvdir}/bin/pip", 'install', '.');
	$this->doit_in_sourcedir($python, "setup.py", "install");
}

sub build_makefile {
	my $this=shift;
	my $builddir = abs_path($this->get_builddir());


	doit('mkdir', '-p', $builddir);


	$this->do_make(@_);
}

sub build_py {
	my $this=shift;

	$this->doit_in_builddir('mkdir', '-p', 'something');
}

sub test {
	my $this=shift;
	if (-e $this->get_sourcepath("setup.py")) {
		$this->test_python(@_);
	} elsif (-e $this->get_sourcepath("Makefile")) {
		$this->test_makefile(@_);
	}
}

sub test_python {
}

sub test_makefile {
	my $this=shift;
	$this->make_first_existing_target(['test', 'check'], @_);
}

sub install {
	my $this=shift;
	if (-e $this->get_sourcepath("setup.py")) {
		$this->install_python(@_);
	} elsif (-e $this->get_sourcepath("Makefile")) {
		$this->install_makefile(@_);
	}
}

sub install_python {
    my $this = shift;
    my $destdir = shift;
    my $pip = $this->get_pip();
    my $python = $this->get_python();
    my $sourcepackage = $this->sourcepackage();
    my $venv = $this->get_venv_builddir();
    my $prefix = $this->get_install_root();
    my $builddir = abs_path($this->get_builddir());
    my $install_root = $this->get_install_root();

    # Before we copy files, let's make the symlinks in the 'usr/local'
    # relative to the build path.
    my @files_in_local = <"$venv/local/*">;
    foreach (@files_in_local) {
        if ( -l $_ ) {
            my $target = readlink;
            my $relpath = File::Spec->abs2rel($target, "$venv/local");
            my $basename = Debian::Debhelper::Dh_Lib->basename($_);
            unlink;
            symlink($relpath, $_);
       }
    }

    $this->doit_in_builddir('mkdir', '-p', $destdir);
    $this->doit_in_builddir('cp', '-r', '-T', '.', $destdir);
    # doit('find', $destdir, '-name', '.git', '-type', 'd', '-exec', 'rm', '-R', '-f', '{}', ';'); # remove all the .git folders so they are not part of the package

    my $new_python = "$prefix/$sourcepackage/bin/python";

    # Fix shebangs so that we use the Python in the final location
    # instead of the Python in the build directory
    my @files = read_dir("$destdir$prefix/$sourcepackage/bin", prefix => 1);
    my @scripts = grep { -T } @files;

    for my $script (@scripts) {
	    my $mode = (stat($script))[2];  # remember perms as edit_file does not keep them

	    edit_file { s|^#!.*bin/(env )?python|#!$new_python| } $script;

	    chmod $mode & 07777, $script;
    }

    my $pth_file = "$destdir$prefix/$sourcepackage/lib/python2.7/site-packages/easy-install.pth";
    if (-T $pth_file) {
	    my $mode = (stat($pth_file))[2];  # remember perms as edit_file does not keep them

            print "$builddir$install_root\n";

	    edit_file { s|$builddir$install_root|$install_root|g } $pth_file;

	    chmod $mode & 07777, $pth_file;
    } else {
	    print "Did not find $pth_file\n";
    }
}

sub install_makefile {
        my $this=shift;
        my $destdir=shift;
        $this->make_first_existing_target(['install'],
                "DESTDIR=$destdir",
                "AM_UPDATE_INFO_DIR=no", @_);
}

sub clean {
	my $this=shift;
	if (-e $this->get_sourcepath("setup.py")) {
		$this->clean_python();
	} elsif (-e $this->get_sourcepath("Makefile")) {
		$this->clean_makefile();
	}
}

sub clean_python {
	my $this=shift;
	$this->rmdir_builddir();
        doit('rm', '-rf', '.pybuild/');
        doit('find', '.', '-name', '*.pyc', '-exec', 'rm', '{}', ';');
}

sub clean_makefile {
        my $this=shift;
        if (!$this->rmdir_builddir()) {
                $this->make_first_existing_target(['distclean', 'realclean', 'clean'], @_);
        }
}

1
