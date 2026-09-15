Reftalk
===================
by User:GreenC (en.wikipedia.org)
Copyright 2019-2026
MIT License

Info
========
Reftalk is a Wikipedia bot that adds `{{reflist-talk}}` to talk page sections that need one.

A talk page section containing `<ref>` tags but no `<references />` or equivalent renders
its citations in an auto-generated list at the foot of the page, detached from the
discussion they belong to. Reftalk finds those sections and adds `{{reflist-talk}}` at the bottom of that section.

It also removes empty `<ref></ref>` tags. Named ones (`<ref name="x"></ref>`) are left alone.

See [WP:Bots/Requests for approval/GreenC bot 8](https://en.wikipedia.org/wiki/Wikipedia:Bots/Requests_for_approval/GreenC_bot_8)
and the run history at [User:GreenC bot/Job 8](https://en.wikipedia.org/wiki/User:GreenC_bot/Job_8).

How it decides
========
For each talk page it compares two counts:

* how many reference lists the page actually renders
* how many explicit reflist templates its wikitext contains

If the first is larger, something is rendering without a template, and the bot walks the
page section by section to find where.

The rendered count comes from `action=parse`

Requirements
========
* GNU Awk 5.4+
* [BotWikiAwk](https://github.com/greencardamom/BotWikiAwk) - provides the libraries,
  `wikiget` (OAuth API access) and `allpages.awk` (article list builder). Requires a version
  from September 2026+ which includes `bin/allpages.awk`
* A user account with bot flag permissions

All API reads go through `wikiget -U`, which carries OAuth credentials. That is not only politeness: the OAuth account holds 
`apihighlimits`, so a request returns 500 titles instead of 50. This is optional however, you can use wikiget without OAuth but it 
will be slower and possibly more time outs. Without OAuth, set `G["apibatch"] = 50`

Installation
========

1. Install BotWikiAwk and follow its setup, including OAuth credentials for wikiget.

2. Clone Reftalk:

		git clone https://github.com/greencardamom/Reftalk

2a. **This repository is configured for the bot as it runs on en.wikipedia under
    User:GreenC.** Every value that identifies an operator or a wiki is collected at the
    top of each program, under a `---- per-wiki ----` banner. Nothing outside those
    blocks needs editing. See Configuring below.

3. Create `dat/` and `log/` under the home path.

4. Follow `static/0README` to build `static/templates` - the templates the bot treats as
   an existing reflist. The list in this repo is of en.wikipedia template names.

5. Set both programs executable and check the shebang points at your awk.

Configuring
========

Both programs carry the same identity block at the very top:

		home      = /path/to/reftalk/            # path ends in "/"
		emailfp   = /path/to/secrets/myname.email
		userid    = User:MY_NAME

`emailfp` points at a file containing a single line, your email address. It is read at
run time, so the address stays out of the source and out of git.

`reftalk.awk`, under `---- per-wiki ----`:

		G["hostname"]  "en"                      # wikiget -l target
		G["domain"]    "wikipedia.org"           # wiki is <hostname>.<domain>
		G["template"]  "reflist-talk"            # the template the bot adds
		G["botpage"]   "User:GreenC bot/Job 8"   # credited in every edit summary
		G["re1"]       "^(Wikipedia talk[:]|User talk[:])"

`G["template"]` must exist on the target wiki. {{reflist-talk}} has interwiki versions on
55 wikis, but check the local name and that its behaviour matches.

`G["re1"]` matches titles that are *already* a talk page, which are worked on directly
rather than via their `Talk:` page. These are English namespace names - on de.wikipedia
it would be `^(Wikipedia Diskussion[:]|Benutzer Diskussion[:])`.

`cron-reftalk.awk`, under `---- per-wiki ----`:

		G["hostname"]  "en"
		G["domain"]    "wikipedia.org"
		G["jobpage"]   "User:GreenC bot/Job 8"   # "" to keep no public run table
		G["minpages"]  5000000                   # sanity floor for a rebuilt list

Set `G["jobpage"]` to your own page, or to `""` to disable it - the cycle then touches no
page other than the talk pages themselves.

`G["minpages"]` is an en.wikipedia article count sanity check. A new list smaller than this aborts the
cycle with the previous list left intact, on the theory that a short crawl means a broken
one. On a smaller wiki every cycle would abort until this is lowered.

BotWikiAwk is also operator-specific
========
The framework underneath has its own hardcoded values, which a fresh install must change:

		lib/botwiki.awk   StopButton, UserPage   - point at User:GreenC bot's pages
		lib/syscfg.awk    Exe["from_email"], Exe["to_email"]

`StopButton` is the page the bot polls to decide whether it may edit - leaving it pointed
at another operator's page means your bot stops when theirs does.

Running
========

Everything below is driven by `cron-reftalk.awk`, which performs one complete cycle:

		archive the previous run's logs
		build a fresh article list
		validate it
		install it and record the cutoff date
		run reftalk
		update the public run table

		./cron-reftalk.awk              # one full cycle
		./cron-reftalk.awk -d           # dry run: log every step, execute none
		./cron-reftalk.awk -s 20250901  # force a cutoff date
		./cron-reftalk.awk -h           # usage

From cron, run quarterly:

		AWKPATH=.:/path/to/BotWikiAwk/lib:/usr/share/awk
		PATH=...:/path/to/BotWikiAwk/bin
		0 3 1 1,4,7,10 * cd /path/to/reftalk && ./cron-reftalk.awk

A cycle takes about 1.5 days for en.wikipedia. It refuses to start if a
previous cycle, reftalk, or allpages is still running, so a cron firing on top of a run
still in progress is a no-op rather than two workers on the same state files.

The cutoff date
========
Reftalk skips any talk page not edited since the previous run. That date comes from, in
order of precedence:

1. `-s YYYYMMDD` manually set via `cron-reftalk`
2. the mtime of the `dat/all-pages` being replaced - automatically determined
3. `2001-01-15`, the launch of Wikipedia, when there is no previous list - so a first run
   sweeps everything

Whichever wins is written to `dat/laststamp`, which `reftalk` reads at startup. A run with
the wrong cutoff is not an error - it silently does nothing.

Mail
========
* `NOTIFY: cron-reftalk run N started` - once a cycle is committed and reftalk launches
* `NOTIFY: reftalk has completed processing all articles!` - on a clean finish
* `NOTIFY: cron-reftalk FAILED` / `aborted` - anything else

The start mail matters for an unattended quarterly job: a cron that never fires at all
otherwise looks exactly like a run quietly in progress.

Stopping and restarting
========
Stop it with [User:GreenC bot/button](https://en.wikipedia.org/wiki/User:GreenC_bot/button),
or kill the process - both are safe.

Stopping and restarting picks up where it left off. `log/all-pages.done` records each 1000-article block and `log/all-pages.offset` 
the position within a block; the last block is re-done, which is harmless because `reftalk` is idempotent. A page it already fixed now 
has the template. Restarts are logged to `log/restart`.

Logs
========
Under `log/`, previous runs are archived to `.<date>` at the start of each cycle:

		discovered        pages edited
		error             sections skipped, with the reason
		syslog            talk pages that do not exist, API warnings
		restart           each resume
		all-pages.done    blocks completed - the resume point
		all-pages.offset  position within the current block
		cron-reftalk.log  the cycle itself
		allpages.log      article list build

Files
========

		reftalk.awk       the bot
		cron-reftalk.awk  unattended cron cycle driver
		static/templates  templates counted as an existing reflist
		dat/all-pages     the article list, rebuilt each cycle
		dat/laststamp     cutoff date for the current run
