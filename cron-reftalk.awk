#!/usr/local/bin/gawk -bE

#
# cron-reftalk - run a full reftalk cycle unattended
#
#   crontab (AWKPATH and PATH are already set globally there):
#     0 3 1 1,4,7,10 * cd /home/greenc/toolforge/reftalk && ./cron-reftalk.awk
#
# Replaces what used to be a by-hand sequence: archiving the logs, rebuilding the
# article list, setting reftalk's cutoff date, and starting the crawl.
#
#   -f <file>      article list to use instead of crawling a fresh one
#   -s <YYYYMMDD>  cutoff date, overriding every other source
#   -j             leave the job table alone - for tests and one-off runs
#   -d             dry run: log every step, execute none
#   -h             usage
#
# Buckets:  G[] - config and paths
#           P[] - command-line parameters
#           Exe[] - executables, inherited from syscfg.awk plus the two programs below
#
# Framework globals (bare by requirement): BotName, Home, Agent, Engine, and getopt's
# Optind / Opterr / Optarg / C / opts
#

BEGIN { # cfg

  _defaults = "home      = /home/greenc/toolforge/reftalk/ \
               emailfp   = /home/greenc/scripts/secrets/greenc.email \
               userid    = User:GreenC \
               version   = 1.0 \
               copyright = 2026"

  asplit(G, _defaults, "[ ]*[=][ ]*", "[ ]{9,}")
  BotName = "cron-reftalk"
  Home = G["home"]
  Engine = 3

  Agent = BotName "-" G["version"] "-" G["copyright"] " (" G["userid"] "; mailto:" strip(readfile(G["emailfp"])) ")"

}

@include "botwiki.awk"
@include "library.awk"

BEGIN { # paths and thresholds

  G["dat"]  = G["home"] "dat/"
  G["log"]  = G["home"] "log/"

  G["allpages"] = G["dat"] "all-pages"          # the article list reftalk walks
  G["newpages"] = G["dat"] "all-pages.new"      # built here, swapped in once it checks out
  G["stampfp"]  = G["dat"] "laststamp"          # unix ts reftalk reads as its cutoff
  G["wlog"]     = G["log"] "cron-reftalk.log"
  G["donelog"]  = G["log"] "all-pages.done"

  # Files archived to .<date> at the start of a cycle
  G["archive"] = "restart error discovered syslog nochange all-pages.done all-pages.offset cron-reftalk.log allpages.log"

  # ---- per-wiki. Everything below changes if this is not en.wikipedia ----

  G["hostname"] = "en"
  G["domain"]   = "wikipedia.org"

  # Public run table, updated at the start and end of each cycle. Set to "" to keep no
  # public log, and the cycle touches no page other than the talk pages themselves
  G["jobpage"]  = "User:GreenC bot/Job 8"

  # A new list must clear both, or the cycle aborts leaving the previous list in place.
  # The floor is an en.wikipedia article count - a smaller wiki needs its own, or every
  # cycle aborts as "below the floor"
  G["minpages"]  = 5000000   # absolute floor
  G["shrinkpct"] = 90        # and at least this % of the previous list

  # ---- not normally changed ----

  G["fqdn"]   = G["hostname"] "." G["domain"]
  G["jobtmp"] = G["dat"] "jobpage.tmp"

  # With no previous list there is no mtime to derive a cutoff from. Fall back to the
  # launch of Wikipedia rather than a recent date, so a virgin run sweeps everything
  G["epoch"] = "20010115"

  # Placed in the Pages edited cell while a cycle runs, replaced by the count when it
  # finishes. A cycle that dies leaves it behind; the next start clears it
  G["inprogress"] = "<span style=\"color:red\">'''In progress'''</span>"

  Exe["allpages"] = "allpages.awk"              # on PATH via ~/scripts
  Exe["reftalk"]  = G["home"] "reftalk.awk"

  P["dryrun"] = 0
  P["laststamp"] = ""                           # -s, overrides everything below

}

BEGIN { # parse args and run

  Optind = Opterr = 1
  while ((C = getopt(ARGC, ARGV, "df:js:h")) != -1) {
    opts++
    if (C == "d")
      P["dryrun"] = 1
    else if (C == "j")
      P["nojob"] = 1
    else if (C == "f") {
      P["listfile"] = Optarg
      if (!checkexists(P["listfile"])) {
        stdErr(BotName ": -f no such file: \"" P["listfile"] "\"")
        exit 2
      }
    }
    else if (C == "s") {
      P["laststamp"] = Optarg
      if (P["laststamp"] !~ /^[0-9]{8}$/) {
        stdErr(BotName ": -s takes a date as YYYYMMDD, not \"" P["laststamp"] "\"")
        exit 2
      }
    }
    else if (C == "h") {
      usage()
      exit 0
    }
    else {
      usage()
      exit 2
    }
  }

  exit (main() ? 0 : 1)

}

# -----------------------------------------------------------

function usage() {

  print BotName " - run a full reftalk cycle unattended"
  print ""
  print "Usage: " BotName ".awk [-f <file>] [-s YYYYMMDD] [-j] [-d] [-h]"
  print ""
  print "  -f <file>      article list to use instead of crawling a fresh one, for a"
  print "                 backlog run off a dump scan. Sets the cutoff to " G["epoch"] " so"
  print "                 nothing is passed over as unedited, and skips the size floor"
  print "                 a crawled list has to clear."
  print "  -s <YYYYMMDD>  cutoff date for reftalk, overriding every other source."
  print "                 Otherwise the mtime of the list being replaced, or " G["epoch"]
  print "                 when there is no previous list."
  print "  -j             leave " G["jobpage"] " alone - no In progress row"
  print "                 at the start, no count at the end. For tests and one-off"
  print "                 runs whose totals do not belong on the public record."
  print "  -d             dry run: log every step, execute none"
  print "  -h             this help"
  print ""
  print "Cycle: archive logs -> build a new article list -> run reftalk"
  print "Exit:  0 ok, 1 cycle failed or was skipped, 2 bad arguments"

}

#
# main() - one cycle
#
function main(   other, adate, oldstamp, oldn, newn, rc, started, startep, ts, runno, resume) {

  started = curtime()
  startep = systime()

  # A cycle runs for well over a day. A quarterly cron landing on top of one still in
  # progress would put two workers on the same state files - see reftalk's all-pages.done
  other = running("cron[-]reftalk[.]awk")
  if (other) {
    logmsg("skipping: " BotName " already running as pid " other)
    return 0
  }
  # Matches both spellings - it is usually started as ./reftalk, the symlink. The
  # leading [^-] keeps cron-reftalk.awk from matching itself
  other = running("[^-]reftalk([.]awk)?([ ]|$)")
  if (other) {
    logmsg("skipping: reftalk already running as pid " other)
    return 0
  }
  other = running("allpages([.]awk)?([ ]|$)")
  if (other) {
    logmsg("skipping: allpages already running as pid " other)
    return 0
  }

  # A cycle stopped part way through its list has its logs, list and cutoff all still
  # in place, and all-pages.done holds the resume point. Setting up again would archive
  # that away and send reftalk back to line 1, so the setup is skipped entirely and the
  # crawl picks up where it stopped. Everything after it still runs, which is what puts
  # the count on the job table
  resume = interrupted()

  if (resume) {

    # The month on the job table is the month the cycle began in, not the one it was
    # resumed in, so the In progress row started back then is the row filled in
    startep = cyclestart(startep)

    logmsg("=== " BotName " " G["version"] " resuming " started (P["dryrun"] ? " (DRY RUN)" : ""))
    logmsg("an earlier cycle stopped mid-list - skipping setup, reftalk resumes from " lastblock())

    if (!empty(P["listfile"]))
      logmsg("note: -f is ignored while resuming - the installed list is kept")

    newn = nlines(G["allpages"])
  }

  else {

    adate = archivedate()

    # Roll this log before anything else writes to it, so each cycle gets a clean one
    rollfile(G["wlog"], adate)

    logmsg("=== " BotName " " G["version"] " starting " started (P["dryrun"] ? " (DRY RUN)" : ""))

    # The previous list's mtime becomes reftalk's cutoff: talk pages untouched since the
    # last crawl cannot need anything. Read it before the list is replaced
    oldstamp = 0
    oldn = 0
    if (checkexists(G["allpages"])) {
      oldstamp = int(sys2var(Exe["date"] " -r " shquote(G["allpages"]) " +%s"))
      oldn = nlines(G["allpages"])
      logmsg("previous list: " oldn " titles, built " strftime("%Y-%m-%d", oldstamp, 1))
    }
    else
      logmsg("previous list: none")

    if (empty(P["listfile"]))
      newn = buildlist(oldn)
    else
      newn = uselist()

    if (newn < 0)
      return 0

    # Nothing destructive happens until the new list is in hand and has checked out
    archivelogs(adate)

    ts = cutoff(oldstamp)

    if (!swaplist(ts))
      return 0

    # Show the run as under way before it starts. Cosmetic, so a failure here is logged
    # but does not stop the cycle
    runno = startrow(startep)

    notifystart(started, oldn, newn, ts, runno)

  }

  rc = runreftalk()

  logmsg("=== finished " curtime() " rc=" rc)

  notify(rc, started, oldn, newn)

  # Only on a clean finish - a partial run's count would go on the record as final
  if (rc == 0)
    updatehistory(nlines(G["log"] "discovered"), startep)

  return (rc == 0)

}

#
# jobtable() - read the job page and locate the run table
#
#  Fills a[] with the page lines and meta[] with start / endi / cnt / n. Returns 0 if
#  the table is not where it should be, in which case the page is left alone
#
function jobtable(a, meta,   fp, n, i) {

  delete a
  delete meta

  fp = sys2var(Exe["wikiget"] " -l " G["hostname"] " -w " shquote(G["jobpage"]))
  if (empty(fp)) {
    logmsg("ERROR: history: could not read " G["jobpage"])
    return 0
  }

  n = split(fp, a, "\n")
  meta["n"] = n

  # Anchored on the table markup, not the heading or the collapse title - those get
  # reworded by hand
  for (i = 1; i <= n; i++) {
    if (a[i] ~ /^[{][|] class="wikitable"/) {
      meta["start"] = i
      break
    }
  }

  # Rows look like:  | 10 || September 2025 || 1,469
  for (i = meta["start"] + 1; meta["start"] && i <= n; i++) {
    if (a[i] ~ /^[|][}]/) {
      meta["endi"] = i
      break
    }
    if (a[i] ~ /^[|][ ]*[0-9]+[ ]*[|][|]/ && a[i] !~ /In progress/)
      meta["cnt"]++
  }

  if (!meta["start"] || !meta["endi"] || !meta["cnt"]) {
    logmsg("ERROR: history: run table not found in " G["jobpage"])
    return 0
  }

  return 1

}

#
# jobwrite() - save the rebuilt page
#
function jobwrite(b, m, summary,   out, cmd, res) {

  out = join(b, 1, m, "\n")

  printf "%s", out > G["jobtmp"]
  close(G["jobtmp"])

  cmd = Exe["wikiget"] " -l " G["hostname"] " -E " shquote(G["jobpage"]) \
        " -S " shquote(summary) " -P " shquote(G["jobtmp"])
  res = sys2var(cmd)
  sys2var(Exe["rm"] " -f " shquote(G["jobtmp"]))

  if (res ~ /[Ss]uccess/)
    return 1

  logmsg("ERROR: history: edit failed - " res)

  return 0

}

#
# startrow() - mark the run as under way on the public table
#
#  Any In progress row still standing is from a cycle that died, so it is dropped and
#  its number reused rather than left to accumulate
#
function startrow(startep,   a, meta, b, m, i, when, line) {

  if (P["nojob"]) {
    logmsg("job table: left alone (-j)")
    return 0
  }

  if (empty(G["jobpage"]))
    return 0

  if (!jobtable(a, meta))
    return 0

  when = strftime("%B %Y", startep)
  line = "| " (meta["cnt"] + 1) " || " when " || " G["inprogress"]

  logmsg("history: marking run " (meta["cnt"] + 1) " " when " in progress")
  if (P["dryrun"])
    return meta["cnt"] + 1

  m = 0
  for (i = 1; i <= meta["n"]; i++) {

    if (i > meta["start"] && i < meta["endi"]) {
      if (a[i] ~ /^[|][-]/ && a[i + 1] ~ /In progress/)
        continue
      if (a[i] ~ /In progress/)
        continue
    }

    if (i == meta["endi"]) {
      b[++m] = "|-"
      b[++m] = line
    }

    b[++m] = a[i]
  }

  if (!jobwrite(b, m, "bot history - run " (meta["cnt"] + 1) " started")) {
    logmsg("history: could not mark the run in progress - continuing anyway")
    return 0
  }

  logmsg("history: " G["jobpage"] " marked in progress")

  return meta["cnt"] + 1

}

#
# updatehistory() - put the final count on the public table
#
#  Fills in the In progress row left by startrow(). If it is gone - hand-edited, or the
#  start mark failed - a new row is appended instead
#
function updatehistory(edited, startep,   a, meta, b, m, i, c, parts, when, done) {

  # Checked here as well as in startrow(), which a resumed cycle never reaches
  if (P["nojob"]) {
    logmsg("job table: left alone (-j) - " commafy(edited) " pages not recorded")
    return 1
  }

  if (empty(G["jobpage"]))
    return 1

  if (edited < 1) {
    logmsg("history: nothing edited, leaving " G["jobpage"] " alone")
    return 1
  }

  if (!jobtable(a, meta)) {
    notifyfail("the run table could not be located in " G["jobpage"] " - it was not updated")
    return 0
  }

  when = strftime("%B %Y", startep)

  for (i = meta["start"] + 1; i < meta["endi"]; i++) {
    if (index(a[i], "|| " when " ||") && a[i] !~ /In progress/) {
      logmsg("history: " when " already recorded - not editing")
      return 1
    }
  }

  logmsg("history: recording " commafy(edited) " pages for " when)
  if (P["dryrun"])
    return 1

  m = 0
  done = 0
  for (i = 1; i <= meta["n"]; i++) {

    if (!done && i > meta["start"] && i < meta["endi"] && a[i] ~ /In progress/) {
      c = split(a[i], parts, /[|][|]/)
      if (c >= 3) {
        a[i] = parts[1] "||" parts[2] "|| " commafy(edited)
        done = 1
      }
    }

    if (!done && i == meta["endi"]) {     # no start mark to fill in - append instead
      b[++m] = "|-"
      b[++m] = "| " (meta["cnt"] + 1) " || " when " || " commafy(edited)
      done = 1
    }

    b[++m] = a[i]
  }

  if (!jobwrite(b, m, "update bot history - " commafy(edited) " pages")) {
    notifyfail("the run table edit to " G["jobpage"] " failed")
    return 0
  }

  logmsg("history: " G["jobpage"] " updated")

  return 1

}

#
# commafy() - 22459 to 22,459
#
#  Not sprintf("%'d"), which needs the locale set - true under cron, not for a run by
#  hand, and the table should not vary by who started it
#
function commafy(n,   s, out) {

  s = sprintf("%d", int(n))
  while (length(s) > 3) {
    out = "," substr(s, length(s) - 2) out
    s = substr(s, 1, length(s) - 3)
  }

  return s out

}

#
# running() - pid of a process matching re, or 0
#
#  Filter in awk, not the pipeline: a "| grep reftalk" would match its own shell
#
function running(re,   i, a, c, line, sp, pid, args, me, parent) {

  me = int(PROCINFO["pid"])
  parent = int(PROCINFO["ppid"])

  c = split(sys2var(Exe["ps"] " -eo pid=,args="), a, "\n")

  for (i = 1; i <= c; i++) {

    line = strip(a[i])
    sp = index(line, " ")
    if (sp < 2)
      continue

    pid = int(substr(line, 1, sp - 1))
    args = substr(line, sp + 1)

    if (pid == me || pid == parent)
      continue
    if (args !~ re)
      continue

    return pid
  }

  return 0

}

#
# interrupted() - 1 if a cycle was stopped part way through its list
#
#  reftalk writes endall as the last line of all-pages.done on reaching the end of the
#  list. Any other last line means there is list still to walk
#
function interrupted(   d) {

  if (!checkexists(G["donelog"]))
    return 0

  d = strip(sys2var(Exe["tail"] " -n 1 " shquote(G["donelog"])))

  return (d !~ /endall/ && !empty(d))

}

#
# lastblock() - the block reftalk will resume at, for the log line
#
function lastblock(   d) {

  d = strip(sys2var(Exe["tail"] " -n 1 " shquote(G["donelog"])))
  sub(/[ \t].*$/, "", d)

  return (empty(d) ? "the start" : "block " d)

}

#
# cyclestart() - unix time the interrupted cycle began, or fallback
#
function cyclestart(fallback,   d) {

  d = sys2var(Exe["head"] " -n 1 " shquote(G["donelog"]))
  if (match(d, /[0-9]{8}/))
    return d82unix(substr(d, RSTART, RLENGTH))

  return fallback

}

#
# archivedate() - the date to stamp this cycle's archived logs with
#
#  The first line of all-pages.done is when the previous reftalk run began. Falls
#  back to today on a first run
#
function archivedate(   d) {

  if (checkexists(G["donelog"])) {
    d = sys2var(Exe["head"] " -n 1 " shquote(G["donelog"]))
    if (match(d, /[0-9]{8}/))
      return substr(d, RSTART, RLENGTH)
  }

  return sys2var(Exe["date"] " +%Y%m%d")

}

#
# rollfile() - move one file aside to .<date>, never overwriting an existing archive
#
function rollfile(fp, adate,   dest, i) {

  if (!checkexists(fp))
    return 1

  dest = fp "." adate
  for (i = 2; checkexists(dest); i++)
    dest = fp "." adate "-" i

  if (P["dryrun"]) {
    logmsg("  would archive " basename(fp) " -> " basename(dest))
    return 1
  }

  sys2var(Exe["mv"] " " shquote(fp) " " shquote(dest))

  return !checkexists(fp)

}

#
# archivelogs() - the previous cycle's logs, plus this program's own
#
function archivelogs(adate,   i, n, a) {

  logmsg("archiving logs to ." adate)

  n = split(G["archive"], a, " ")
  for (i = 1; i <= n; i++) {
    if (a[i] == "cron-reftalk.log")   # already rolled, and being written to now
      continue
    rollfile(G["log"] a[i], adate)
  }

}

#
# buildlist() - crawl a fresh article list, returning its line count or -1 on failure
#
#  Built under a temporary name and checked before anything is replaced: a short or
#  failed crawl must not cost the previous list, which is the only copy
#
function buildlist(oldn,   cmd, rc, n, floor) {

  if (checkexists(G["newpages"])) {
    logmsg("removing stale " basename(G["newpages"]))
    if (!P["dryrun"])
      sys2var(Exe["rm"] " -f " shquote(G["newpages"]))
  }

  cmd = Exe["allpages"] " -c " BotName " -o " shquote(G["newpages"]) " -g " shquote(G["log"] "allpages.log")

  logmsg("building list: " cmd)
  if (P["dryrun"])
    return (oldn ? oldn : G["minpages"])

  rc = system(cmd)
  if (rc != 0) {
    logmsg("ERROR: allpages exited " rc " - keeping the previous list")
    notifyfail("allpages exited " rc)
    return -1
  }

  n = nlines(G["newpages"])

  floor = G["minpages"]
  if (oldn > 0 && int(oldn * G["shrinkpct"] / 100) > floor)
    floor = int(oldn * G["shrinkpct"] / 100)

  if (n < floor) {
    logmsg("ERROR: new list has " n " titles, below the " floor " floor - keeping the previous list")
    notifyfail("new list has " n " titles, below the " floor " floor")
    return -1
  }

  logmsg("new list: " n " titles")

  return n

}

#
# uselist() - install a supplied article list, returning its line count or -1 on failure
#
#  The -f path. No crawl and no size floor - a backlog list is meant to be small. Copied
#  rather than moved so the caller's file survives the run
#
function uselist(   n) {

  if (checkexists(G["newpages"])) {
    logmsg("removing stale " basename(G["newpages"]))
    if (!P["dryrun"])
      sys2var(Exe["rm"] " -f " shquote(G["newpages"]))
  }

  n = nlines(P["listfile"])
  if (n < 1) {
    logmsg("ERROR: " P["listfile"] " is empty - keeping the previous list")
    notifyfail(P["listfile"] " is empty")
    return -1
  }

  logmsg("supplied list: " n " titles from " P["listfile"])

  if (P["dryrun"])
    return n

  sys2var(Exe["cp"] " " shquote(P["listfile"]) " " shquote(G["newpages"]))
  if (nlines(G["newpages"]) != n) {
    logmsg("ERROR: could not stage " P["listfile"])
    notifyfail("could not stage " P["listfile"])
    return -1
  }

  return n

}

#
# swaplist() - put the new list in place and record the cutoff reftalk will read
#
function swaplist(ts) {

  if (P["dryrun"]) {
    logmsg("  would install " basename(G["newpages"]) " as " basename(G["allpages"]))
    logmsg("  would write cutoff " strftime("%Y-%m-%d", ts) " to " basename(G["stampfp"]))
    return 1
  }

  sys2var(Exe["mv"] " " shquote(G["newpages"]) " " shquote(G["allpages"]))
  if (!checkexists(G["allpages"])) {
    logmsg("ERROR: could not install the new list")
    notifyfail("could not install the new list")
    return 0
  }

  print ts > G["stampfp"]
  close(G["stampfp"])
  logmsg("cutoff " strftime("%Y-%m-%d", ts) " written to " basename(G["stampfp"]))

  return 1

}

#
# cutoff() - the date reftalk will treat as "skip anything untouched since"
#
#   -s              whatever was asked for, no questions
#   previous list   its mtime - talk pages untouched since that crawl cannot need anything
#   neither         the launch of Wikipedia, so a first run sweeps the lot
#
function cutoff(oldstamp) {

  if (!empty(P["laststamp"])) {
    logmsg("cutoff from -s: " P["laststamp"])
    return d82unix(P["laststamp"])
  }

  # A supplied list is exactly the pages an mtime cutoff would pass over, so inheriting
  # one would walk the whole list and act on nothing
  if (!empty(P["listfile"])) {
    logmsg("cutoff for the supplied list: " G["epoch"])
    return d82unix(G["epoch"])
  }

  if (oldstamp)
    return oldstamp

  logmsg("no previous list and no -s: falling back to " G["epoch"])

  return d82unix(G["epoch"])

}

#
# d82unix() - YYYYMMDD to unix time. Same conversion reftalk uses, so the two agree
#
function d82unix(s) {

  return strftime("%s", mktime(substr(s, 1, 4) " " substr(s, 5, 2) " " substr(s, 7, 2) " 0 0 0"), 1)

}

#
# runreftalk() - the crawl itself. Hours to days
#
function runreftalk(   cmd, rc) {

  cmd = Exe["reftalk"]

  logmsg("running: " cmd)
  if (P["dryrun"])
    return 0

  rc = system(cmd)
  if (rc != 0)
    logmsg("ERROR: reftalk exited " rc)

  return rc

}

#
# notify() - one mail at the end of a cycle
#
function notify(rc, started, oldn, newn,   subj, body) {

  # reftalk sends its own "has completed processing all articles!" when it finishes, so
  # a success here would just be a second mail saying the same thing
  if (rc == 0) {
    logmsg("cycle completed - no mail, reftalk sends its own")
    return
  }

  subj = "NOTIFY: " BotName " FAILED (rc=" rc ")"

  body = "started  " started "\n"
  body = body "finished " curtime() "\n\n"
  body = body "previous list " oldn " titles\n"
  body = body "new list      " newn " titles\n\n"
  body = body "edited   " nlines(G["log"] "discovered") "\n"
  body = body "errors   " nlines(G["log"] "error") "\n"
  body = body "log      " G["wlog"] "\n"

  if (P["dryrun"]) {
    logmsg("would email: " subj)
    return
  }

  email(Exe["from_email"], Exe["to_email"], subj, body)

}

#
# notifystart() - mail once the cycle is committed and reftalk is about to run
#
#  Sent at the start so a silent failure to launch at all - bad crontab, machine down -
#  reads as a missing mail rather than as a run still quietly in progress. Carries the
#  cutoff, the one value that silently makes the whole run a no-op if it is wrong
#
function notifystart(started, oldn, newn, ts, runno,   subj, body) {

  subj = "NOTIFY: " BotName (runno ? " run " runno : "") " started"

  body = "started   " started "\n\n"
  body = body "new list  " commafy(newn) " titles"
  body = body (oldn ? "  (previous " commafy(oldn) ")" : "") "\n"
  body = body "cutoff    " strftime("%Y-%m-%d", ts) "  - talk pages untouched since are skipped\n\n"
  body = body "log       " G["wlog"] "\n"
  if (!empty(G["jobpage"]))
    body = body "page      https://" G["fqdn"] "/wiki/" gsubi(" ", "_", G["jobpage"]) "\n"

  if (P["dryrun"]) {
    logmsg("would email: " subj)
    return
  }

  email(Exe["from_email"], Exe["to_email"], subj, body)

}

#
# notifyfail() - mail an aborted cycle, where nothing was replaced
#
function notifyfail(reason) {

  if (P["dryrun"]) {
    logmsg("would email failure: " reason)
    return
  }

  email(Exe["from_email"], Exe["to_email"], "NOTIFY: " BotName " aborted", reason "\n\nThe previous article list and logs are untouched.\nSee " G["wlog"] "\n")

}

#
# logmsg() - one line to the cycle log, and to stderr on a dry run
#
#  Quiet on stderr otherwise: cron mails anything a job prints, and a cycle logs plenty
#
function logmsg(s) {

  print curtime() " " s >> G["wlog"]
  close(G["wlog"])

  if (P["dryrun"])
    stdErr(s)

}

#
# nlines() - line count of a file, 0 if absent
#
function nlines(fp,   a) {

  if (!checkexists(fp))
    return 0
  split(sys2var(Exe["wc"] " -l " shquote(fp)), a, " ")

  return int(strip(a[1]))

}

#
# curtime() - local time, matching the format reftalk writes
#
function curtime() {

  return strftime("%Y%m%d-%H:%M:%S", systime())

}
