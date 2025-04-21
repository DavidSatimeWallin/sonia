module main

import net.http
import os
import os.cmdline
import term

import readline

const sonia_version = '0.1.3.2'

/*

	@todo
	- put bash-things in .sonia/bashrc and append to ~/.bashrc
	- some kind of time estimate per step..?
	- add support for fish and zsh..?
	- add update-function for conf repo, plugins and cargo utilites

*/
struct Cfg {
	bashrc string =
		normalize_target(
			cmdline.option(
				os.args,
				'--bashrc',
				'\$HOME/.bashrc'
			)
		)
	target_folder string =
		normalize_target(
			cmdline.option(
				os.args,
				'--target',
				'\$HOME/.sonia'
			)
		)
	nvim_cfg_folder string =
		normalize_target(
			cmdline.option(
				os.args,
				'--nvim-cfg',
				'\$HOME/.config/nvim'
			)
		)
	delete_plugins string =
		cmdline.option(
			os.args,
			'--delete-plugins',
			'yes'
		)
	cargo_bin string = normalize_target('\$HOME/.cargo/bin')
	git_repo string =
		cmdline.option(
			os.args,
			'--git-repo',
			'https://github.com/davidsatimewallin/slimvim'
		)
	mut:
	target_bin string = 'bin'
	target_repo string = 'conf'
}

fn main() {

	if '--help' in os.args || '-help' in os.args {
		println(term.header('Sonia v$sonia_version - by David Satime Wallin <david@snogerup.com>', '.'))
		print('\nUSAGE:\n\n\t${term.bold('sonia [flags]')}\n\n')
		println('FLAGS:')
		print('\n\t${term.bold('--bashrc')}\t\tthe location of the .bashrc -file. default is \$HOME/.bashrc')
		print('\n\t${term.bold('--target')}\t\tthe location of the .sonia -folder. default is \$HOME/.sonia')
		print('\n\t${term.bold('--nvim-cfg')}\t\tthe location of the nvim -config folder. default is \$HOME/.config/nvim')
		print('\n\t${term.bold('--delete-plugins')}\tif set to "yes" \$HOME/.vim/plugged will be deleted')
		print('\n\t${term.bold('--git-repo')}\t\tthe git (https) repo addr. default is https://github.com/dvwallin/slimvim')
		print('\n\t${term.bold('--help')}\t\t\tshows this help section')
		print('\n\t${term.bold('--license')}\t\tshows the pretty MIT license text')
		print('\n\n')
	    exit(1)
	}

	if '--license' in os.args || 'license' in os.args {
		print('Copyright © 2021 David Satime Wallin <david@dwall.in>\n
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n
THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.')
		exit(1)
	}


	tell('starting install..')
	mut cfg := Cfg{}

	cfg.build_paths()

	path_exists := cfg.path_exists() or {
		fail(err.msg())
		return
	}

	cfg.create_directories_if_not_exists() or {
		fail(err.msg())
	}

	if !path_exists {
		cfg.handle_rc_files() or {
			fail(err.msg())
		}
	}

	cfg.download_nvim_appimage() or {
		fail(err.msg())
	}

	install_rustup() or {
		fail(err.msg())
	}

	install_rust_utilities() or {
		fail(err.msg())
	}

	cfg.clone_config() or {
		fail(err.msg())
	}

	cfg.symlink_config() or {
		fail(err.msg())
	}

	cfg.install_vim_plugins() or {
		fail(err.msg())
	}

	cfg.install_coc_plugins() or {
		fail(err.msg())
	}

	tell('install complete!')
}

fn fail(input string) {
	println(term.fail_message(input))
	exit(1) // good idea..?!?!
}

fn (c Cfg) install_coc_plugins() ! {
	tell('installing coc plugins')
	vim_exec := [
		c.target_bin,
		'nvim.appimage'
	].join('/')
	res1 := os.execute('$vim_exec +CocInstall coc-phpls +qall')
	if res1.exit_code != 0 {
		return error('could not install coc-phpls: $res1.output')
	}
	res2 := os.execute('$vim_exec +CocInstall coc-go +qall')
	if res2.exit_code != 0 {
		return error('could not install coc-go: $res2.output')
	}
	tell('coc plugins installed!')
}

fn (c Cfg) install_vim_plugins() ! {
	tell('installing vim plugins')

	if c.delete_plugins == 'yes' {
		plugged_dir := [os.home_dir(),'.vim','plugged'].join('/')
		if os.exists(plugged_dir) {
			os.rmdir_all(plugged_dir) or {
				return err
			}
		}
	}

	vim_exec := [
		c.target_bin,
		'nvim.appimage'
	].join('/')
	result := os.execute('$vim_exec +PlugInstall +qall')
	if result.exit_code != 0 {
		return error('could not install vim plugins: $result.output')
	}
	tell('vim plugins installed!')
}

fn install_vimplug() ! {
	tell('installing vim-plug')
	result := os.execute(
	'sh -c \'curl -fLo ${os.home_dir()}/.local/share/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim\''
	)
	if result.exit_code != 0 {
		return error('could not install vim-plug: $result.output')
	}
	tell('vim-plug installed!')
}

fn (c Cfg) symlink_config() ! {
	tell('creating symlink')
	repo := [c.target_repo, 'slimvim'].join('/')
	link := [c.nvim_cfg_folder, 'init.vim'].join('/')
	if	os.exists(link) &&
		os.is_link(link) {
			tell('removing old symlink ($link)')
			os.rm(link) or {
				return err
			}
			tell('old symlink ($link) removed')
		}
	os.symlink(
		'$repo/.vimrc',
		link
	) or {
		return error(
			'could not symlink $repo/.vimrc into $link'
		)
	}
	tell('symlink created')
}

fn (c Cfg) clone_config() ! {
	tell('cloning config files')

	repo := [c.target_repo, 'slimvim'].join('/')
	if !os.exists(repo) {
		result := os.execute(
			'git clone $c.git_repo $repo'
		)
		if result.exit_code != 0 {
			return error('could not clone $c.git_repo into $repo')
		}
	}

	tell('config files cloned!')
}

fn install_rustup() ! {
	tell('installing rustup')
	result := os.execute('curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y')
	if result.exit_code != 0 {
		return error('could not install rustup')
	}
	tell('rustup installed!')
}

fn install_rust_utilities() ! {
	tell('installing rust utilities')
	// temp fix?
	mut skip_fix := false
	toml_file := [
			os.home_dir(),
			'.cargo',
			'config.toml'
		].join('/')
	if os.exists(toml_file) {
		toml_c := os.read_file(toml_file) or {
			return err
		}
		if toml_c.contains('git-fetch-with-cli') {
			skip_fix = true
		}
	}
	if !skip_fix {
		mut f := os.open_append(toml_file) or {
			return err
		}
		gcfg := '[net]\ngit-fetch-with-cli = true'
		f.writeln(gcfg) or {
			return err
		}
		f.close()
	}
	// temp fix end

	installed := os.execute('cargo install --list')
	if !installed.output.contains('ripgrep') {
		tell('installing ripgrep through cargo')
		res1 := os.execute('cargo install ripgrep --force')
		if res1.exit_code != 0 {
			return error('could not install ripgrep: $res1.output')
		}
	}
	if !installed.output.contains('bat') {
		tell('installing bat through cargo')
		res2 := os.execute('cargo install --locked bat --force')
		if res2.exit_code != 0 {
			return error('could not install bat: $res2.output')
		}
	}
	if !installed.output.contains('fd-find') {
		tell('installing fd-find through cargo')
		res3 := os.execute('cargo install fd-find --force')
		if res3.exit_code != 0 {
			return error('could not install fd-find: $res3.output')
		}
	}
	tell('rust utilities installed!')
}

fn (c Cfg) create_directories_if_not_exists() ! {
	if !os.exists(c.target_folder) {
		os.mkdir(c.target_folder) or {
			return error('$c.target_folder: $err')
		}
		tell('created $c.target_folder')
	}
	if !os.exists(c.target_bin) {
		os.mkdir(c.target_bin) or {
			return error('$c.target_bin: $err')
		}
		tell('created $c.target_bin')
	}
	if !os.exists(c.target_repo) {
		os.mkdir(c.target_repo) or {
			return error('$c.target_repo: $err')
		}
		tell('created $c.target_repo')
	}
	if !os.exists(c.nvim_cfg_folder) {
		os.mkdir_all(c.nvim_cfg_folder) or {
			return error('$c.nvim_cfg_folder: $err')
		}
		tell('created $c.nvim_cfg_folder')
	}
}

fn tell(input string) {
	println(term.ok_message(input))
}

fn (c Cfg) download_nvim_appimage() ! {
	mut skip_download := false

	output_file := [
		c.target_bin,
		'nvim.appimage'
	].join('/')

	if os.exists(output_file) {
		skip_download = true
		println(term.warn_message('$output_file exists'))
		mut response := readline.read_line('Remove old nvim.appimage? (y/n) ') or {
			return err
		}
		response = response.trim_space()
		if response == 'y' {
			skip_download = false
		}
		else {
			tell('not downloading $output_file')
		}
	}
	if !skip_download {
		tell('downloading $output_file')
		http.download_file(
			'https://github.com/neovim/neovim/releases/download/v0.11.0/nvim-linux-x86_64.appimage',
			output_file
		) or {
			return error('could not download nvim: ${err.msg()}')
		}
		tell('downloaded $output_file')
		os.chmod(output_file, 0o755) or {
			return error('could not chmod $output_file: $err')
		}
		tell('made $output_file executable')
	}
}

fn (c Cfg) path_exists() !bool {
	content := os.read_file(c.bashrc) or {
		return error('could not read from $c.bashrc: ${err.msg()}')
	}
	if content.contains('#sonia-cfg') {
		return true
	}
	return false
}

fn (c Cfg) handle_rc_files() ! {
	soniarc := [c.target_folder, 'soniarc'].join('/')
	soniarc_content := '#sonia-cfg\nexport PATH="$c.target_bin:\$PATH"\nalias vim="nvim.appimage"'

	mut soniarc_file:= os.open_append(soniarc) or {
		return error('could not access $soniarc: ${err.msg()}')
	}
	soniarc_file.writeln(soniarc_content) or {
		return error('could not write $soniarc_content to $soniarc: ${err.msg()}')
	}
	soniarc_file.close()

	str := '#sonia-cfg\nif [ -f $soniarc ]; then\n\t. $soniarc\nfi\n'
	mut bashrc_file:= os.open_append(c.bashrc) or {
		return error('could not access $c.bashrc: ${err.msg()}')
	}
	bashrc_file.writeln(str) or {
		return error('could not write $str to $c.bashrc: ${err.msg()}')
	}
	bashrc_file.close()
}

fn normalize_target(input string) string {
	mut output := input.replace('\$HOME', os.home_dir())
	output = output.replace('~', os.home_dir())
	return os.real_path(output)
}

fn (mut c Cfg) build_paths() {
	c.target_bin = [c.target_folder, c.target_bin].join('/')
	c.target_repo = [c.target_folder, c.target_repo].join('/')
}
