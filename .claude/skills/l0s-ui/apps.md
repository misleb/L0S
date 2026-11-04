# From a description to an app

How to turn what a person asks for ("a to-do list with a box to type
in and a check on each item") into an L0S app, by the shortest path
that works. Read this first; `SKILL.md` beside it is the toolkit and
compositor in full, `l0-code` the language. `user/apps/todo` is the
worked example, made exactly this way.

## The workflow

1. **Scaffold.** `tools/l0s-app-new NAME "Title" user/apps/NAME --bundle
   APP` in L0S's tree (the builder's sessions: `l0s-app-new NAME
   "Title"` in their folder). It writes `NAME.l0` (state, view, update,
   step, `ui_run`), `NAME_test.l0`, `main.l0` and `preview.l0`, and with
   `--bundle` the bundle's manifest and `icon.draw`. It checks, builds
   and previews as written: change it, don't start from nothing. In
   the tree, give it `LIBS_NAME := $(RENDER) $(WMLIB) $(UI_CORE)
   $(UI_WINDOW)` in the Makefile, as `LIBS_todo` is.
2. **Name the parts.** For each thing the description mentions, find
   its row in the table below: the widget, the actions it sets off,
   what the state keeps, and the update's line. Write the state first,
   a record with a named field each, then the view, then the update.
3. **Check as you go.** `l0 fmt FILE` then `l0 check` (in the tree,
   `make -s build/check/user/apps/NAME/main.l0.ok`). L0 is not a
   language you know: let the checker tell you.
4. **Preview and look.** Write a scene in `preview.l0` for each state
   that matters (empty, full, a dialog open, a long text), then `make
   preview APP=NAME` (builders: `l0s-app-preview NAME`) and Read the
   PNGs in `build/preview/NAME/` (`preview/`). It takes seconds, and
   shows what a screen test would only find on the board: a toolbar
   wider than its window, text cut short, a control out of place. Fix
   and look again.
5. **Test and build.** In the tree: host tests of the update and the
   view (`testing.l0`'s `ui_laid`, `ui_has_target`, `ui_has_text`,
   `ui_target_at`), the l0s-dev checklist for an app, and a screen test
   if it is one of L0S's own (pin its pixels' places with
   `ui_target_at` in a host test first, as `todo_test.l0`'s
   `test_placed` does). Builders: `l0s-app-build NAME`.

## The shape

```
(data Todo (Todo (tasks (list Task)) (entry UiEntryText) (asking bool)))   ; state: named fields
(def todo_new () Todo ...)                                                 ; as it opens
(def todo_view ((t Todo)) UiWidget ...)                                    ; state -> widgets, afresh each time
(def todo_update ((t Todo) (action (list int)) (ev UiEvent)) Todo          ; one test of the action a line
  (if (eq action "app.add") (todo_added t)
      (starts_with action "new.") (.entry t (ui_entry_update "new" (.entry t) action ev))
      ...
      t))
(def todo_step ((t Todo) (action (list int)) (ev UiEvent) (w UiWin)) (UiStepped Todo)
  (UiStepped w (todo_update t action ev)))                                 ; the window's own asks go here
(def todo () int (ui_run "todo" "To Do" 480 520 (todo_new) todo_view todo_step))
```

- **Widgets carry action names, not callbacks.** A click sets off the
  name; the update matches it. Name an app's own `app.VERB` or
  `app.VERB.KEY` (`app.delete.3`, read back with `drop_n`), a dialog's
  `dialog.VERB`; widgets with a name of their own set off `NAME.…`
  (below).
- **The step is where the window is asked of**: `app.start` comes once
  as it opens. Focus an entry there (`ui_win_focusing w "NAME.entry"`),
  set an alarm (`ui_win_alarm`), ask a server (`ui_win_ask`).
- **Read before you replace.** Several fields changed by one action:
  read each new value with `let`, then replace them nested, as the
  gallery's `controlled` does; reading the record after replacing a
  field copies it (`l0 check` warns).
- **Keep what a widget shows in the state**: a switch's `bool`, an
  entry's `UiEntryText`, a list's first row, a grid's `UiGridState`.
  Nothing is kept in a widget.

## What a person says, and what to write

| They say | Write in the view | It sets off | The state keeps | The update |
|---|---|---|---|---|
| a button, "a way to X" | `(UiButton "app.x" ICON LABEL (UiBtnSuggested) SENSITIVE)`, kinds `UiBtnRegular` `UiBtnFlat` `UiBtnDestructive` | `app.x` on release, Enter or Space with the focus | — | `(eq action "app.x") ...` |
| text, a number, a heading | `(UiLabel S KIND ALIGN)`, kinds `UiBody` `UiDimmed` `UiHeading` `UiLarge`; `ui_value S` in properties | — | the value | — |
| a page with a title | `(ui_page TITLE LINE CHILDREN)`, padded 18, children 12 apart | — | — | — |
| a toolbar, buttons over content | `(ui_toolbar_page START STATUS END BODY)`, body given the rest | the buttons' | — | — |
| a line at the bottom saying how many | `(ui_with_footer BODY TEXT)` | — | — | — |
| a heading with buttons beside it | `(ui_heading_row TITLE BUTTONS)` | the buttons' | — | — |
| a box to type in | `(UiEntry "new" TEXT PLACEHOLDER (ui_entry_w N))`, N characters wide | `new.edit` keys, `new.activate` Enter, `new.place.N` | `UiEntryText` | `(.entry s (ui_entry_update "new" (.entry s) action ev))`; focus it in the step |
| a box to write a message in, that grows | `(UiTextArea "say" TEXT PLACEHOLDER 200 MOST)` in a `UiExpand`, in a column (it is as high as its rows only there) | as an entry's: `say.edit`, `say.activate` Enter, `say.place.N` | `UiEntryText` | as an entry's |
| a picture, an image | `(UiKeyed (append "image." PATH) (UiPicture PIXELS))`, PIXELS a `UiCov` of `png_read`, `png_fit` to the room it is shown in | — | the pixels, decoded once | — |
| a chat, messages | `UiLines` of `UiPara`s of kind `UiLineOutgoing` (theirs, at the end) and `UiLineIncoming` (to them, at the start) | `log.scrollto.N` | the messages | `ui_lines_first` |
| two panes side by side, half each | `(UiBox (UiH) 0 (cons (UiExpand (UiShrinks A)) (cons (UiSeparator (UiV)) (cons (UiExpand (UiShrinks B)) ...))))` | — | — | — |
| a list of things | `(UiList (UiListData "items" ROWS FIRST))`, rows `(ui_list_row KEY TITLE SUBTITLE)`, `(.start row W)`, `(.end row W)`, `(.icon row NAME)`, `(.actionable row false)`; in a `UiExpand` or a page to fill it | `items.select.KEY`, `items.scrollto.N` | the items, the first row | `(ui_select_key "items" action)`; `(ui_list_first first "items" action)` |
| an item you can tick | `(UiCheck "task.K" DONE LABEL)`, at a row's start with label `""` | `task.K.toggle` | a `bool` | `(ui_toggled "task.K" done action)` |
| an on/off setting | `(UiSwitch "wifi" ON)`, alone or at a row's end | `wifi.toggle` | a `bool` | `(ui_toggled "wifi" on action)` |
| a slider, an amount | `(UiScale "vol" V MIN MAX WIDTH)` | `vol.set.N` pressed or dragged, `vol.step.±1` Left/Right | an `int` | `(ui_scale_value "vol" v MIN MAX action)` |
| a progress, a level | `(UiLevel PERCENT WIDTH)` | — | an `int` | — |
| a status: ok, warning, error | `(UiStatus TONE TEXT)`, tones `UiGood` `UiWarn` `UiBad` `UiAccentTone` `UiNeutral` | — | — | — |
| a choice of a few | `(UiToggleGroup "mode" (ui_toggles LABELS) KEY)` | `mode.select.KEY` | the key | `(ui_select_key "mode" action)` |
| settings, name and value | `(UiProps (cons (UiProp NAME WIDGET) ...))` | the widgets' | — | — |
| tabs | `(UiTabBar "tabs" TABS KEY)`, `(UiTab KEY TITLE)` | `tabs.select.KEY`, `tabs.close.KEY` | tabs, the key | `ui_select_key`, `ui_tab_close_key`; `(ui_without ui_tab_key k ts)`, `(ui_key_after ui_tab_key k ts sel)` |
| "are you sure?" | `(UiModal PAGE (ui_confirm HEADING LINES "dialog.x" LABEL DESTRUCTIVE))` while asking | `dialog.x`, `dialog.cancel` | a `bool` | `(eq action (ui_cancel_action))` |
| a dialog that asks for a value | `(UiModal PAGE (ui_alert_form HEADING LINES (cons (UiProps ...) ...) BUTTONS))` | its entry's, its buttons' | the entry | focus its entry as it opens |
| a menu | `(UiPopover PAGE (UiMenu "menu" (UiBelow "app.menu") ITEMS))`, `(UiItem ACTION LABEL ON)` | the item's, `menu.dismiss` | whether open | — |
| nothing yet, empty | `(UiStatusPage ICON TITLE WHAT-TO-DO)` | — | — | — |
| busy, waiting | `(UiSpinner PHASE 16)`, turned in the step: `ui_win_alarm w (add (clock_ns) (ui_spinner_ns))`, and on `(ui_is_alarm ev)` `ui_spinner_next` and the alarm again | — | the phase | — |
| a timer, a clock | the alarm as above, its own period | — | the time | on `(ui_is_alarm ev)` |
| a table of columns | `(UiGrid (UiGridView "procs" COLUMNS ROWS STATE))`, or with a toolbar `ui_grid_page` | `procs.select.KEY`, `procs.sort.N`, scrolls | `UiGridState` | `ui_grid_action`, keys `ui_grid_key` with `(ui_win_scroller w "procs")` |
| sections beside a pane | `(ui_split (UiSidebar (ui_sidebar_w) ROWS "side" KEY) PANE)` | `side.select.KEY` | the key | `ui_select_key` |
| text that wraps, a log, a chat | `(UiLines (UiLinesData "log" PARAS FIRST))`, `(UiPara TEXT KIND ICON ACTION)` | `log.scrollto.N` | paragraphs, first (-1 to follow the end) | `ui_lines_first` |
| a grid of icons | `(UiIconView (UiIconData "files" TILES STATE))` | `files.select.KEY` | `UiIconState` | `ui_icon_action` |
| something drawn | `UiDrawingArea` | `NAME.drawing` | — | needs a loop of its own, as Terminal's: not `ui_run` |

**Icons** are named as GNOME's: `ui_icon_names` in `icons.l0` lists
them (`list-add`, `user-trash`, `object-select`, `view-refresh`,
`folder`, `system-search`, `open-menu`...). A new one is GNOME's SVG
copied in (`SKILL.md`, Scale). **Colors and sizes** come from
`theme.l0` only: no hex in an app.

## Layout, as it works here

- A box lays its children along at their natural sizes, `UiExpand`
  ones sharing what is left; across, each child gets all the room, and
  a button or a label of `UiCenter` sits in its middle, so a column of
  them is centered. Put a row of buttons in `(UiBox (UiH) (ui_space_s)
  ...)` to keep them at its start.
- A window's size is the app's to choose, in the desktop's pixels:
  480 by 520 for a list, 640 by 440 for a table. Add up a toolbar: 6
  in, each widget and 6 between; an entry of N characters is
  `ui_entry_w N`. The preview shows when it does not fit.
- Text is measured with `ui_text_w S (ui_text_font) BOLD 1`, never as
  characters times a width, and is cut with `...` where it has no room.
- Spacing is the theme's: `ui_space_s` 6, `ui_space_m` 12,
  `ui_space_l` 18.

## What the toolkit does not do

No alpha, blur or shadows; text is ASCII, in two faces; an entry does
not scroll its text, select, copy or paste; scrolling is by whole rows;
a list's rows are all one height, two lines at most; a slider steps a
twentieth of its range; nothing animates but by the app's alarm. An
app that needs more writes it from what is there (a `UiDrawingArea` it
paints itself), or changes the library (builders: in their worktree,
for the person to merge). `spec/toolkit.md`'s Limits has the whole
list.
