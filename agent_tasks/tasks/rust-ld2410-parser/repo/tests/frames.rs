use ld2410::{Parser, Report, TargetState};

const HEADER: [u8; 4] = [0xF4, 0xF3, 0xF2, 0xF1];
const FOOTER: [u8; 4] = [0xF8, 0xF7, 0xF6, 0xF5];

fn target(state: u8, moving: u16, me: u8, stationary: u16, se: u8, detection: u16) -> Vec<u8> {
    let mut t = vec![state];
    t.extend(moving.to_le_bytes());
    t.push(me);
    t.extend(stationary.to_le_bytes());
    t.push(se);
    t.extend(detection.to_le_bytes());
    t
}

fn frame(kind: u8, target: &[u8], extras: &[u8]) -> Vec<u8> {
    let mut data = vec![kind, 0xAA];
    data.extend(target);
    data.extend(extras);
    data.extend([0x55, 0x00]);
    let mut f = HEADER.to_vec();
    f.extend((data.len() as u16).to_le_bytes());
    f.extend(data);
    f.extend(FOOTER);
    f
}

fn basic() -> Vec<u8> {
    frame(0x02, &target(3, 120, 55, 87, 40, 95), &[])
}

const EXPECTED: Report = Report {
    state: TargetState::MovingAndStationary,
    moving_cm: 120,
    moving_energy: 55,
    stationary_cm: 87,
    stationary_energy: 40,
    detection_cm: 95,
};

fn feed(parser: &mut Parser, bytes: &[u8]) -> Vec<Report> {
    bytes.iter().filter_map(|&b| parser.push(b)).collect()
}

#[test]
fn one_basic_frame() {
    assert_eq!(feed(&mut Parser::new(), &basic()), vec![EXPECTED]);
}

#[test]
fn frames_split_across_reads_and_noise() {
    let mut p = Parser::new();
    let f = basic();
    let mut out = feed(&mut p, &[0x00, 0x13, 0xF4, 0x99]);
    out.extend(feed(&mut p, &f[..7]));
    out.extend(feed(&mut p, &f[7..]));
    out.extend(feed(&mut p, &[0xF4, 0xF4, 0xF3]));
    out.extend(feed(&mut p, &f));
    assert_eq!(out, vec![EXPECTED, EXPECTED]);
}

#[test]
fn a_false_start_inside_the_header_still_syncs() {
    let mut bytes = vec![0xF4, 0xF3];
    bytes.extend(basic());
    assert_eq!(feed(&mut Parser::new(), &bytes), vec![EXPECTED]);
}

#[test]
fn bad_footer_or_markers_are_dropped_and_the_parser_recovers() {
    let mut bad_footer = basic();
    let n = bad_footer.len();
    bad_footer[n - 1] = 0x00;
    let mut bad_head = basic();
    bad_head[7] = 0xAB;
    let mut bad_tail = basic();
    bad_tail[n - 6] = 0x56;
    let mut stream = Vec::new();
    for bad in [bad_footer, bad_head, bad_tail] {
        stream.extend(bad);
        stream.extend(basic());
    }
    assert_eq!(feed(&mut Parser::new(), &stream), vec![EXPECTED; 3]);
}

#[test]
fn engineering_frames_report_their_basic_part() {
    let mut extras = vec![8, 8];
    extras.extend([10u8; 9]);
    extras.extend([20u8; 9]);
    extras.extend([0x40, 0x01]);
    let f = frame(0x01, &target(1, 300, 70, 0, 0, 300), &extras);
    assert_eq!(f[4], 35, "engineering data is 35 bytes");
    let r = feed(&mut Parser::new(), &f);
    assert_eq!(r.len(), 1);
    assert_eq!(r[0].state, TargetState::Moving);
    assert_eq!(r[0].moving_cm, 300);
    assert_eq!(r[0].detection_cm, 300);
}

#[test]
fn command_acks_and_oversized_frames_are_ignored() {
    let ack = [
        0xFD, 0xFC, 0xFB, 0xFA, 0x04, 0x00, 0xFF, 0x01, 0x00, 0x00, 0x04, 0x03, 0x02, 0x01,
    ];
    let mut oversized = HEADER.to_vec();
    oversized.extend(200u16.to_le_bytes());
    oversized.extend([0x02, 0xAA, 0x01]);
    let mut stream = ack.to_vec();
    stream.extend(oversized);
    stream.extend(basic());
    assert_eq!(feed(&mut Parser::new(), &stream), vec![EXPECTED]);
}

#[test]
fn unknown_target_states_are_not_reported_as_absent() {
    let f = frame(0x02, &target(7, 0, 0, 0, 0, 0), &[]);
    assert_eq!(feed(&mut Parser::new(), &f), vec![]);
}
