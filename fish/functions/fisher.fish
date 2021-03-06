set -g fisher_version 3.2.5

function fisher -a cmd -d "fish package manager"
    set -q XDG_CACHE_HOME; or set XDG_CACHE_HOME ~/.cache
    set -q XDG_CONFIG_HOME; or set XDG_CONFIG_HOME ~/.config

    set -g fish_config $XDG_CONFIG_HOME/fish
    set -g fisher_cache $XDG_CACHE_HOME/fisher
    set -g fisher_config $XDG_CONFIG_HOME/fisher

    set -q fisher_path; or set -g fisher_path $fish_config

    for path in {$fish_config,$fisher_path}/{functions,completions,conf.d} $fisher_cache
        if test ! -d $path
            command mkdir -p $path
        end
    end

    if test ! -e $fisher_path/completions/fisher.fish
        echo "fisher complete" >$fisher_path/completions/fisher.fish
        _fisher_complete
    end

    if test -e $fisher_path/conf.d/fisher.fish
        switch "$version"
            case \*-\*
                command rm -f $fisher_path/conf.d/fisher.fish
            case 2\*
            case \*
                command rm -f $fisher_path/conf.d/fisher.fish
        end
    else
        switch "$version"
            case \*-\*
            case 2\*
                echo "fisher copy-user-key-bindings" >$fisher_path/conf.d/fisher.fish
        end
    end

    switch "$cmd"
        case {,self-}complete
            _fisher_complete
        case copy-user-key-bindings
            _fisher_copy_user_key_bindings
        case ls
            set -e argv[1]
            if test -s "$fisher_path/fishfile"
                set -l file (_fisher_fmt <$fisher_path/fishfile | _fisher_diff R)
                _fisher_ls | _fisher_fmt | command awk -v FILE="$file" "
                    BEGIN { for (n = split(FILE, f); ++i <= n;) file[f[i]] } \$0 in file && /$argv[1]/
                "
            end
        case self-update
            _fisher_self_update (status -f)
        case self-uninstall
            _fisher_self_uninstall
        case -v {,--}version
            _fisher_version (status -f)
        case -h {,--}help
            _fisher_help
        case ""
            _fisher_commit --
        case add rm
            if not isatty
                while read -l arg
                    set argv $argv $arg
                end
            end

            if test (count $argv) = 1
                echo "fisher: invalid number of arguments" >&2
                _fisher_help >&2
                return 1
            end

            _fisher_commit $argv
        case \*
            echo "fisher: unknown flag or command \"$cmd\"" >&2
            _fisher_help >&2
            return 1
    end
end

function _fisher_complete
    complete -ec fisher
    complete -xc fisher -n __fish_use_subcommand -a add -d "Add packages"
    complete -xc fisher -n __fish_use_subcommand -a rm -d "Remove packages"
    complete -xc fisher -n __fish_use_subcommand -a ls -d "List installed packages matching REGEX"
    complete -xc fisher -n __fish_use_subcommand -a help -d "Show usage help"
    complete -xc fisher -n __fish_use_subcommand -a version -d "$fisher_version"
    complete -xc fisher -n __fish_use_subcommand -a self-update -d "Update to the latest version"
    for pkg in (fisher ls)
        complete -xc fisher -n "__fish_seen_subcommand_from rm" -a $pkg
    end
end

function _fisher_copy_user_key_bindings
    if functions -q fish_user_key_bindings
        functions -c fish_user_key_bindings fish_user_key_bindings_copy
    end
    function fish_user_key_bindings
        for file in $fisher_path/conf.d/*_key_bindings.fish
            source $file >/dev/null 2>/dev/null
        end
        if functions -q fish_user_key_bindings_copy
            fish_user_key_bindings_copy
        end
    end
end

function _fisher_ls
    for pkg in $fisher_config/*/*/*
        command readlink $pkg; or echo $pkg
    end
end

function _fisher_fmt
    command sed "s|^[[:space:]]*||;s|^$fisher_config/||;s|^$HOME|~|;s|^\.\/|$PWD/|;s|^github\.com/||;s|^https*://||;s|/*\$||"
end

function _fisher_version -a file
    echo "fisher version $fisher_version $file" | command sed "s|$HOME|~|"
end

function _fisher_help
    echo "usage:"
    echo "       fisher add <PACKAGES>    Add packages"
    echo "       fisher rm  <PACKAGES>    Remove packages"
    echo "       fisher                   Update all packages"
    echo "       fisher ls  [REGEX]       List installed packages matching REGEX"
    echo "       fisher help              Show this help"
    echo "       fisher version           Show the current version"
    echo "       fisher self-update       Update to the latest version"
    echo "       fisher self-uninstall    Uninstall from your system"
    echo "examples:"
    echo "       fisher add jethrokuan/z rafaelrinaldi/pure"
    echo "       fisher add gitlab.com/foo/bar@v2"
    echo "       fisher add ~/path/to/local/pkg"
    echo "       fisher add < file"
    echo "       fisher rm rafaelrinaldi/pure"
    echo "       fisher ls | fisher rm"
    echo "       fisher ls fish-\*"
end

function _fisher_self_update -a file
    set -l url "https://raw.githubusercontent.com/jorgebucaran/fisher/master/fisher.fish"
    echo "fetching $url" >&2
    command curl -s "$url?nocache" >$file.

    set -l next_version (command awk 'NR == 1 { print $4 }' < $file.)
    switch "$next_version"
        case "" $fisher_version
            command rm -f $file.
            if test -z "$next_version"
                echo "fisher: cannot update fisher -- are you offline?" >&2
                return 1
            end
            echo "fisher is already up-to-date" >&2
        case \*
            echo "linking $file" | command sed "s|$HOME|~|" >&2
            command mv -f $file. $file
            source $file
            echo "updated to $fisher_version -- hooray!" >&2
            _fisher_complete
    end
end

function _fisher_self_uninstall
    for pkg in (_fisher_ls)
        _fisher_rm $pkg
    end

    for file in $fisher_cache $fisher_config $fisher_path/{functions,completions,conf.d}/fisher.fish $fisher_path/fishfile
        echo "removing $file"
        command rm -Rf $file 2>/dev/null
    end | command sed "s|$HOME|~|" >&2

    for name in (set -n | command awk '/^fisher_/')
        set -e "$name"
    end

    functions -e (functions -a | command awk '/^_fisher/') fisher
    complete -c fisher --erase
end

function _fisher_commit -a cmd
    set -e argv[1]
    set -l elapsed (_fisher_now)
    set -l fishfile $fisher_path/fishfile

    if test ! -e "$fishfile"
        command touch $fishfile
        echo "created new fishfile in $fishfile" | command sed "s|$HOME|~|" >&2
    end

    set -l rm_pkgs (_fisher_ls | _fisher_fmt)
    for pkg in (_fisher_ls)
        _fisher_rm $pkg
    end
    command rm -Rf $fisher_config
    command mkdir -p $fisher_config

    set -l next_pkgs (_fisher_fmt <$fishfile | _fisher_diff R $cmd (printf "%s\n" $argv | _fisher_fmt))
    set -l new_pkgs (_fisher_fetch $next_pkgs)
    set -l old_pkgs
    for pkg in $rm_pkgs
        if contains -- $pkg $new_pkgs
            set old_pkgs $old_pkgs $pkg
        end
    end

    if test -z "$new_pkgs$old_pkgs$rm_pkgs$next_pkgs"
        echo "nothing to commit -- try adding some packages" >&2
        return 1
    end

    set -l actual_pkgs
    if test "$cmd" = "rm"
        set actual_pkgs $next_pkgs
    else
        for pkg in $next_pkgs
            if contains -- (echo $pkg | command sed "s|@.*||") $new_pkgs
                set actual_pkgs $actual_pkgs $pkg
            end
        end
    end

    printf "%s\n" (_fisher_fmt <$fishfile | _fisher_diff W $cmd $actual_pkgs) >$fishfile

    _fisher_complete

    command awk -v N=(count $new_pkgs) -v O=(count $old_pkgs) -v R=(count $rm_pkgs) -v E=(_fisher_now $elapsed) '
        BEGIN {
            res = fmt("removed", R - O, fmt("updated", O, fmt("added", N - O)))
            printf((res ? res : "done") " in %.2fs\n", E / 1000)
        }
        function fmt(action, n, s) {
            return n ? (s ? s ", " : s) action " " n " package" (n > 1 ? "s" : "") : s
        }
    ' >&2
end

function _fisher_diff -a diff cmd
    set -e argv[1..2]
    command awk -v FS="[[:space:]]*#" -v DIFF="$diff" -v CMD="$cmd" -v ARGSTR="$argv" '
        BEGIN {
            for (n = split(ARGSTR, a, " "); i++ < n;) pkgs[getkey(a[i])] = a[i]
        }
        { k = getkey($1) }
        DIFF == "R" && !(k in pkgs) && $0 = $1
        DIFF == "W" && (/^#/ || !NF || (k in pkgs && $0 = pkgs[k]) || CMD != "rm")
        DIFF == "W" || CMD == "rm" { delete pkgs[k] }
        END {
            for (k in pkgs) {
                if (CMD != "rm" || DIFF == "W") print pkgs[k]
                else print "package not in fishfile: \""k"\"" > "/dev/stderr"
            }
        }
        function getkey(s,  a) {
            return (split(s, a, /@+|:/) > 2) ? a[2]"/"a[1]"/"a[3] : a[1]
        }
    '
end

function _fisher_fetch
    set -l pkg_jobs
    set -l next_pkgs
    set -l local_pkgs
    set -l actual_pkgs
    set -q fisher_user_api_token; and set -l curl_opts -u $fisher_user_api_token

    for i in $argv
        switch $i
            case \~\* /\*
                set -l path (echo "$i" | command sed "s|~|$HOME|")
                if test -e "$path"
                    set local_pkgs $local_pkgs $path
                else
                    echo "fisher: cannot add \"$i\" -- is this a valid file?" >&2
                end
                continue
        end

        command awk -v NAME=$i -v FS=/ '
            BEGIN {
                if (split(NAME, tmp, /@+|:/) > 2) {
                    if (tmp[4]) sub("@"tmp[4], "", NAME)
                    print NAME "\t" tmp[2]"/"tmp[1]"/"tmp[3] "\t" (tmp[4] ? tmp[4] : "master")
                } else {
                    pkg = split(NAME, _, "/") <= 2 ? "github.com/"tmp[1] : tmp[1]
                    tag = tmp[2] ? tmp[2] : "master"
                    print (\
                        pkg ~ /^github/ ? "https://codeload."pkg"/tar.gz/"tag : \
                        pkg ~ /^gitlab/ ? "https://"pkg"/-/archive/"tag"/"tmp[split(pkg, tmp, "/")]"-"tag".tar.gz" : \
                        pkg ~ /^bitbucket/ ? "https://"pkg"/get/"tag".tar.gz" : pkg \
                    ) "\t" pkg
                }
            }
        ' | read -l url pkg branch

        if test ! -d "$fisher_config/$pkg"
            fish -c "
                echo fetching $url >&2
                command mkdir -p $fisher_config/$pkg $fisher_cache/(command dirname $pkg)
                if test ! -z \"$branch\"
                     command git clone $url $fisher_config/$pkg --branch $branch --depth 1 2>/dev/null
                     or echo fisher: cannot clone \"$url\" -- is this a valid url\? >&2
                else if command curl $curl_opts -Ss $url 2>&1 | command tar -xzf- -C $fisher_config/$pkg 2>/dev/null
                    command rm -Rf $fisher_cache/$pkg
                    command mv -f $fisher_config/$pkg/* $fisher_cache/$pkg
                    command rm -Rf $fisher_config/$pkg
                    command cp -Rf {$fisher_cache,$fisher_config}/$pkg
                else if test -d \"$fisher_cache/$pkg\"
                    echo fisher: cannot connect to server -- searching in \"$fisher_cache/$pkg\" | command sed 's|$HOME|~|' >&2
                    command cp -Rf $fisher_cache/$pkg $fisher_config/$pkg/..
                else
                    command rm -Rf $fisher_config/$pkg
                    echo fisher: cannot add \"$pkg\" -- is this a valid package\? >&2
                end
            " >/dev/null &

            set pkg_jobs $pkg_jobs (_fisher_jobs --last)
            set next_pkgs $next_pkgs "$fisher_config/$pkg"
        end
    end

    if test ! -z "$pkg_jobs"
        _fisher_wait $pkg_jobs
        for pkg in $next_pkgs
            if test -d "$pkg"
                set actual_pkgs $actual_pkgs $pkg
                _fisher_add $pkg
            end
        end
    end

    set -l local_path $fisher_config/local/$USER
    for src in $local_pkgs
        command mkdir -p $local_path
        command ln -sf $src $local_path/(command basename $src)
        set actual_pkgs $actual_pkgs $src
        _fisher_add $src --link
    end

    if test ! -z "$actual_pkgs"
        _fisher_fetch (_fisher_deps $actual_pkgs | command awk '!seen[$0]++')
        printf "%s\n" $actual_pkgs | _fisher_fmt
    end
end

function _fisher_deps
    for pkg in $argv
        if test ! -d "$pkg"
            echo $pkg
        else if test -s "$pkg/fishfile"
            _fisher_deps (_fisher_fmt < $pkg/fishfile | _fisher_diff R)
        end
    end
end

function _fisher_add -a pkg opts
    set -l name (command basename $pkg)
    for src in $pkg/{functions,completions,conf.d}/**.* $pkg/*.fish
        set -l target (command basename $src)
        switch $src
            case $pkg/conf.d\*
                set target $fisher_path/conf.d/$target
            case $pkg/completions\*
                set target $fisher_path/completions/$target
            case $pkg/{functions,}\*
                switch $target
                    case uninstall.fish
                        continue
                    case init.fish key_bindings.fish
                        set target $fisher_path/conf.d/$name\_$target
                    case \*
                        set target $fisher_path/functions/$target
                end
        end
        echo "linking $target" | command sed "s|$HOME|~|" >&2
        if test -z "$opts"
            command cp -f $src $target
        else
            command ln -sf $src $target
        end
        switch $target
            case \*.fish
                source $target >/dev/null 2>/dev/null
        end
    end
end

function _fisher_rm -a pkg
    set -l name (command basename $pkg)
    for src in $pkg/{conf.d,completions,functions}/**.* $pkg/*.fish
        set -l target (command basename $src)
        set -l filename (command basename $target .fish)
        switch $src
            case $pkg/conf.d\*
                test "$filename.fish" = "$target"; and emit "$filename"_uninstall
                set target conf.d/$target
            case $pkg/completions\*
                test "$filename.fish" = "$target"; and complete -ec $filename
                set target completions/$target
            case $pkg/{,functions}\*
                test "$filename.fish" = "$target"; and functions -e $filename
                switch $target
                    case uninstall.fish
                        source $src
                        continue
                    case init.fish key_bindings.fish
                        set target conf.d/$name\_$target
                    case \*
                        set target functions/$target
                end
        end
        command rm -f $fisher_path/$target
    end
    if not functions -q fish_prompt
        source "$__fish_datadir$__fish_data_dir/functions/fish_prompt.fish"
    end
end

function _fisher_jobs
    jobs $argv | command awk '/^[0-9]+\t/ { print $1 }'
end

function _fisher_wait
    while for job in $argv
            contains -- $job (_fisher_jobs); and break
        end
    end
end

function _fisher_now -a elapsed
    switch (command uname)
        case Darwin \*BSD
            command perl -MTime::HiRes -e 'printf("%.0f\n", (Time::HiRes::time() * 1000) - $ARGV[0])' $elapsed
        case \*
            math (command date "+%s%3N") - "0$elapsed"
    end
end
