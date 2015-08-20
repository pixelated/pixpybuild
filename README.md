# pixpybuild

pixpybuild is a debian buildhelper that allows us to bundle the user agent with all its resources
into a virtualenv.


## Using pixpybuild

Using pixpybuild is fairly straightforward. First, you need to
define the requirements of your package in `requirements.txt` file, in
[the format defined by pip](https://pip.pypa.io/en/latest/user_guide.html#requirements-files).

To build a package using pixpybuild, you need to add pixpybuild
in to your build dependencies and write following `debian/rules` file:

      %:
              dh $@ --with pixpybuild

## Credits
* [dh-virtualenv](https://github.com/spotify/dh-virtualenv)
* [dh-venv](https://github.com/guilhem/dh-venv)

## License

Copyright (c) 2015 ThoughtWorks, Inc.

pixpybuild is licensed under GPL v3 or later. Full license is available in the `LICENSE` file.

