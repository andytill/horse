%% Copyright (c) 2013, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(horse).

-export([app_perf/1]).
-export([mod_perf/1]).

%% These might be interesting later on.
%% @todo horse_init, horse_end
%% @todo horse_init_per_test, horse_end_per_test

app_perf(App) when is_atom(App) ->
	io:format("Running horse on application ~s~n", [App]),
	ok = ensure_clean_profiling_dir(),
	ok = application:load(App),
	{ok, Modules} = application:get_key(App, modules),
	_ = [mod_perf(M) || M <- lists:sort(Modules)],
	ok.

mod_perf(Mod) when is_atom(Mod) ->
	Exports = Mod:module_info(exports),
	[fun_perf(Mod, Fun) || {Fun, 0} <- Exports, is_horse_function(Fun)],
	ok.

fun_perf(Mod, Fun) when is_atom(Mod), is_atom(Fun) ->
	Self = self(),
	Ref = make_ref(),
	Is_eflame = is_eflame_function(Fun),
	Eflame_output = io_lib:format("profiling/~p_~p.eflame", [Mod, Fun]),
	spawn_link(
		fun() ->
			Before = os:timestamp(),
			case Is_eflame of
				true ->
					Mode = normal_with_children,
					eflame:apply(Mode, Eflame_output, Mod, Fun, []),
					After = os:timestamp(),
					generate_profile_svg(Eflame_output),

					% append this to the end of the test result line to make it
					% clear that tracing was applied, the duration is much higher
					% than without tracing
					Test_info = " PROFILED";
				_ ->
					_Val = Mod:Fun(),
					After = os:timestamp(),
					Test_info = ""
			end,

			% Results.
			Time = timer:now_diff(After, Before),
			"horse_" ++ Name = atom_to_list(Fun),
			io:format("~s:~s in ~b.~6.10.0bs~s~n",
				[Mod, Name, Time div 1000000, Time rem 1000000, Test_info]),
			Self ! {test_complete, Ref}
		end),

	% await test completion
	receive
	    {test_complete, Ref} ->
	    	ok
	after
		30000 ->
			error({timeout, Mod, Fun})
	end,
	ok.

%%
is_horse_function(Fun) ->
	atom_starts_with(Fun, "horse_").

is_eflame_function(Fun) ->
	atom_starts_with(Fun, "horse_eflame_").

%%
atom_starts_with(A, Starts_with) ->
	Starts_with == string:substr(atom_to_list(A), 1, length(Starts_with)).

%%
ensure_clean_profiling_dir() ->
	% can't use file:del_dir because it complains if the directory is not empty
	% and there is no force option
	os:cmd("rm -rf profiling"),
	ok = file:make_dir("profiling").

%%
generate_profile_svg(Eflame_output) ->
	Cmd = io_lib:format(
		"deps/eflame/stack_to_flame.sh < ~s > ~s.svg",
		[Eflame_output,Eflame_output]),
	os:cmd(Cmd).