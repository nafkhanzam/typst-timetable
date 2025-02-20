#import "lib/helper.typ" as lib
#import "lib/default-blocks.typ"

#let timetable(
  data,
  date: datetime.today().display("[day]/[month]/[year]"),
  show-header: true,
  show-alternatives: true,
  show-description: true,
  table-args: (:),
  event-cell: default-blocks.event-cell,
  time-cell: default-blocks.time-cell,
  color-theme: "tab",
) = {
  let lang-dict = (
    title: "Timetable",
    of: "of",
    alternatives: "Alternatives",
    description: "Description",
  )
  if "language" in data {
    for (key, value) in data.language {
      lang-dict.insert(key, value)
    }
  }

  let defaults = data.at("defaults", default: (:))
  let weekdays = data.general.weekdays

  let colors = if type(color-theme) == str {
    lib.load-color-theme(color-theme)
  } else { color-theme }

  let (times, courses, description, slots, alts) = lib.process-timetable-data(data, colors)

  let final-data = times
    .enumerate()
    .map(time => (
      time-cell(time.at(1), lang-dict),
      weekdays
        .enumerate()
        .map(d => slots.at(d.at(0)).at(time.at(0)))
        .map(ev => if ev == none {
          []
        } else if ev.at("occupied", default: false) {
          ()
        } else {
          let cell = event-cell(
            ev,
            show-time: time.at(1).at("show-time", default: defaults.at("show-time", default: false)),
            unique: ev.at("unique", default: true),
          )
          if ev.duration > 0 { table.cell(rowspan: ev.duration + 1, cell) } else { cell }
        })
        .flatten(),
    ).flatten())
    .flatten()

  // Title
  if show-header {
    text(16pt, strong(lang-dict.title + " " + data.general.period))
    " " + lang-dict.of + " " + data.general.person
    if date != none {
      h(1fr)
      date
    }
  }

  // Main Timetable
  table(
    columns: (auto, ..weekdays.len() * (1fr,)),
    stroke: (
      paint: gray,
      thickness: 0.5pt,
      dash: "dashed",
    ),
    ..table-args,
    [],
    ..weekdays.map(day => align(center, day)),
    ..final-data,
  )

  show link: underline

  // Alternatives
  if show-alternatives and alts.len() > 0 {
    text(14pt, lang-dict.alternatives + ":")
    v(-12pt)
    table(
      columns: weekdays.len() * (1fr,),
      column-gutter: 5pt,
      //stroke: gray + 0.5pt,
      stroke: none,
      ..alts.map(ev => event-cell(ev, show-time: true, show-day: true)),
    )
  }

  // Abbreviations
  if show-description {
    text(14pt, lang-dict.description + ":")
    v(-6pt)
    context {
      let h = measure([Hello]).height
      table(
        columns: description.len() + 2,
        stroke: (
          paint: gray,
          thickness: 0.5pt,
          dash: "dashed",
        ),
        ..table-args, // at the moment table does not span the whole width
        none,
        none,
        ..description.map(d => strong(d.title)),
        ..courses
          .filter(c => not c.at("hide-description", default: false))
          .map(c => (
            rect(fill: c.color, width: h, height: h),
            strong(c.abbrv),
            ..description.map(
              d => [#(d.contentfn)(c.at(d.id, default: ""))], // wraps content in link or other stuff
            ),
          ))
          .flatten(),
      )
    }
  }
}
