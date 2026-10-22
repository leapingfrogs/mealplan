# Iteration 5: layout refresh

Make every page work on a phone first and use the room on wide screens,
with one look and one set of building blocks. No new features: the
behaviour in [USER_STORIES.md](../../USER_STORIES.md) is unchanged.

The work started from a screenshot audit of every page at 390 px (iPhone),
1024 px and 4K, logged out and as a member, an owner and a new user. It found
five defects (buttons drawn as plain text, a broken invite field, the shopping
list scrolling sideways, amounts nobody can buy, week chips breaking
mid-word) and no shared navigation, page structure or component set. The
same audit, re-run at the end, is the check that the refresh is done.

## Scope

| In | Out (later, if wanted) |
|---|---|
| App shell: tab bar on phones, sidebar from 1024 px | Customisable navigation, search |
| Theme tokens, self-hosted fonts, a 13 px text floor | A user-chosen accent colour |
| Shared components every page is built from | A component gallery page |
| Week plan, recipes, meals, shopping, household, import, account, onboarding and login laid out for each size | Splitting the household page into title and controls columns on wide screens |
| Light and dark themes | High-contrast theme |

## Look

- **Colour.** Paprika (`#c2410c`; `#f0814a` in the dark theme) on warm
  neutrals, defined as daisyUI themes in `assets/css/app.css`. Pages use the
  theme's names (`primary`, `base-200`, `error`...), never raw colours.
- **Type.** Public Sans for text and Bricolage Grotesque for headings,
  self-hosted in `priv/static/fonts` because the CSP allows no font hosts.
  `text-xs` is 13 px and nothing is smaller; daisyUI's `btn-xs`/`btn-sm` and
  their `lg:`/`xl:` forms are raised to it. From 1536 px the root size grows a
  step, so everything scales up on large screens.
- **Widths.** Each page takes one of three: `max-w-form` (30rem: login,
  onboarding), `max-w-content` (45rem: most pages) or `max-w-wide` (75rem:
  the week plan, shopping).
- **Touch.** Controls are at least 40 px tall, rows and menu items 44 px or
  more on phones.

## App shell

`<Layouts.app>` takes the page's `section` (plan, recipes, meals, shopping,
household, account) and marks it in the navigation.

- **Phones:** a slim top bar (logo, avatar menu) and a fixed tab bar with the
  five sections. The bar's height is the CSS variable `--tab-bar`
  (including the safe area), which sticky bars and toasts sit above.
- **From 1024 px:** a sidebar with the household's name, the sections and
  the account menu (theme, account settings, log out); no tab bar.
- **Logged out:** only the logo and the theme toggle.

## Components

`MealplanWeb.UI`, imported everywhere. Pages are built from these rather
than drawing headers, rows or panels by hand; when a page needs something
they lack, the component is extended.

| Component | Use |
|---|---|
| `page_header` | Title (always the full width), meta line, back link, action buttons, and a ⋯ menu for the rest |
| `section_card` | A titled card of related content or settings; `danger` for a red one |
| `row_list`, `list_row` | Bordered lists; rows wrap the title to two lines, with lead, meta, trailing value and actions |
| `row_menu`, `close_menu/2` | A row's actions behind ⋮ when it has more than one |
| `add_form` | One field and an Add button (slots, members, staples, items, meals) |
| `confirm_panel` | "Are you sure?" in place, listing what's affected; can submit a form (a choice, a typed name) |
| `empty_state` | What goes here, and the action that adds it |
| `chip_group`, `chip` | Toggles such as the slots a meal suits |
| `stepper`, `stepper_field`, `step_field/4` | Servings and head counts, alone or as a form field |
| `collapsible` | A group that opens and closes (ticked items, staples) |
| `sheet` | Bottom sheet on phones, dialog on wider screens |
| `auth_card` | The logged-out pages' card |

Buttons follow one language: primary solid for the page's main action,
outline or plain for secondary ones, ghost for quiet ones and Cancel, red for
destructive ones. Confirmation panels and sheets follow the week plan's
patterns; DaisyUI `alert` isn't used for anything with controls.

## Pages

- **Week plan.** Phones: a strip of the week's days (today marked) and one
  card per day; days earlier this week fold to a one-line summary. From
  1024 px two columns of day cards; from 1280 px seven columns whose slot
  rows line up across the week (a CSS subgrid). Meal chips put the name on
  its own line (up to three lines) with servings and "cooks N" below.
- **Recipes and meals.** Lists of `list_row`s with search; the recipe page
  puts ingredients beside the method from 1024 px, and the editor shows the
  Cooklang source beside the preview from 1280 px (Write and Preview tabs
  below that). The meal page puts its recipes beside the picker.
- **Shopping.** The add field at the top; each row is one tick target with
  the amount on the same line. From 1024 px, items added by hand, Ticked and
  Staples move to a sticky column beside the list; from 1360 px the list
  splits into two columns. The date range and Staples are in the header,
  Copy and Start a new list in the menu.
- **Household.** Section cards for details, meal slots, members, import and
  export, and a red delete card. Slot and member actions are in ⋮ menus;
  Usually feeding is a stepper; deleting asks for the household's name in a
  confirmation panel.
- **Import.** A full-width drop zone; in the preview, names wrap and the
  action stays in a fixed right column.
- **Account and onboarding.** The shared header and cards, sentence case.
- **Logged out.** `/` goes straight to the login page (no "You must log in"
  error). One email field and "Email me a login link"; "Use a password
  instead" turns the same form into the password form. The login link page
  uses the same card.

## Checking a change

New and changed screens are checked at 390 px first, then 1024 px and a wide
screen: no sideways scroll, no text under 13 px, nothing cut off without a
way to see it. The re-audit at the end of this iteration found none of the
first audit's high-severity problems; on a 4K screen at 100% scaling the
wide pages still use about a third of the width, which is acceptable since
such screens normally run at 150 to 200%.
