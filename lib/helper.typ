#let load-color-theme(theme-name, themes-file: "colorthemes.toml") = {
  let theme-dict = toml(themes-file)
  if theme-name in theme-dict {
    theme-dict.at(theme-name).map(c => color.rgb(c.at(0), c.at(1), c.at(2)))
  } else {
    panic("Color Theme `" + theme-name + "` does not exist. Alternatives are: {" + theme-dict.keys().join(", ") + "}")
  }
}

#let description-parser(data) = if "description" in data {
  data.description.map(d => {
    if "title" not in d { d.insert("title", upper(d.id)) }
    let dtype = d.at("type", default: "text")
    if dtype == "link" {
      d.contentfn = x => if x == "" { x } else { link(x, "link") }
    } else if dtype == "content" {
      d.contentfn = x => eval(x, mode: "markup")
    } else {
      d.contentfn = x => x
    }
    d
  })
} else { () }

#let courses-parser(data, colors) = {
  let colors = colors.rev()
  let courses = ()

  for (cabbrv, cvalues) in data.courses.pairs() {
    if cvalues.at("hide", default: false) {
      continue
    }
    if "color" in cvalues {
      cvalues.color = eval(cvalues.color)
    } else {
      cvalues.color = colors.pop()
    }
    cvalues.abbrv = cabbrv // handle abbreviation and name differently
    cvalues.priority = cvalues.at("priority", default: 0)
    courses.push(cvalues)
  }

  courses
}

#let parse-time(time) = {
  let split = if type(time) in ("integer", "float") { (time,) } else { time.split(":") }
  let hour = int(split.at(0))
  let minute = if split.len() > 1 {
    int(split.at(1))
  } else {
    0
  }

  return (hour, minute)
}

#let sum-time(a, b, negative: false) = {
  let (ah, am) = parse-time(a)
  let (bh, bm) = parse-time(b)
  if negative {
    bh = -bh
    bm = -bm
  }

  am += bm
  ah += bh + calc.div-euclid(am, 60)
  am = calc.rem-euclid(am, 60)

  if ah < 10 { "0" }
  str(ah) + ":"
  if am < 10 { "0" }
  str(am)
}

#let process-timetable-data(data, colors) = {
  let time-overlap(ev, time) = time.start <= ev.start and ev.start < time.end or time.start < ev.end and ev.end <= time.end or ev.start <= time.start and time.start < ev.end or ev.start < time.end and time.end <= ev.end

  let defaults = data.at("defaults", default: (:))
  let default-duration = defaults.at("duration", default: "02:00")
  let weekdays = data.general.weekdays

  let slots = weekdays.map(_ => data.general.times.map(_ => none))
  let alts  = ()
  let times = data.general.times.map(
    time => (
      ..time,
      start: if "start" in time { time.start } else { sum-time(time.end, default-duration, negative: true) },
      end: if "end" in time { time.end } else { sum-time(time.start, default-duration) }
    )
  )

  let courses = courses-parser(data, colors)

  for (i, day) in weekdays.enumerate() {
    let day-evs = courses.map(
      course => course.at("events", default: (:)).pairs().map(
        evtype => evtype.at(1).filter(
          ev => not ev.at("hide", default: false) and ev.day == day
        ).map(k => (
          ..course, // get all properties from the course
          ..k,      // get all properties from the event, included later hence can overwrite course properties (e.g. for priority)
          kind: evtype.at(0),
          // change if absent with special values
          start: if "start" in k { k.start } else { sum-time(k.end, default-duration, negative: true) },
          end: if "end" in k { k.end } else { sum-time(k.start, default-duration) }
        )).flatten()
      ).flatten()
    ).flatten().sorted(key: ev => ev.priority).rev()

    for ev in day-evs {
      let conflict = false
      let already_conflict = false
      for (j, time) in times.enumerate() {
        if time-overlap(ev, time) {
          let conflict_j = j
          if slots.at(i).at(j) == none {
            // also check the duration
            let duration = times.slice(j + 1).enumerate()
              .find(x => not time-overlap(ev, x.at(1)))
            let duration = if duration == none { times.len() - j - 1 } else { duration.at(0) }
            ev.insert("duration", duration)

            if duration > 0 {
              for k in range(duration) {
                if slots.at(i).at(j + k + 1) != none {
                  conflict = true
                  conflict_j = j + k + 1
                  break
                }
              }
            }
            if not conflict and not already_conflict {
              slots.at(i).at(j) = ev
              for k in range(duration) {
                  slots.at(i).at(j + k + 1) = ("occupied": true) // notify that this spot is already occupied
              }
            }
          } else {
            conflict = true
            conflict_j = j
          }
          if conflict {
            if not already_conflict {
              alts.push(ev)
            }
            slots.at(i).at(conflict_j).insert("unique", false)
            already_conflict = true
          } else {
            break
          }
        }
        if conflict {
          break
        }
      }
    }
    for (j, ev) in slots.at(i).enumerate() {
      if ev != none and "start" in ev {
        for alt in alts {
          if time-overlap(ev, alt) {
            slots.at(i).at(j).insert("unique", false)
          }
        }
      }
    }
  }

  let description = description-parser(data)

  (times, courses, description, slots, alts)
}