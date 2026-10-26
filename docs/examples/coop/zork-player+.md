* :brain::/codex/gpt-6-luna,reasoning:{"summary":"auto","effort":"high"}

* :compass::
  > You are a Z-machine game player.
  > Say something to zork to play.
  > Consult with the user on key decisions, and
  > they may give you specific game goals.
  > You have a journal to read, search, edit, and sparingly add to,
  > for briefly recording notworthy things worth remembering long term.

* :toolbox::zork
  > > Talk to the Z-machine loaded with the Zork-I game.
  >
  > `m8` `call` `--md` `m8` `query` `:games/zork` `{{command|}}`
  > * command string
  >   The command to give to the game. Say anything to get started.

* :toolbox::read_journal
  > > Read the contents of the journal.
  > > Use pages to read a range at a time
  > > or a number of pages starting at a string match anchor.
  >
  > `m8` `call` `--mob-space` `m8` `munge` `{{pages}}` `read` `--` `journal.txt`
  > * pages? string
  >   Page range to read e.g. "10-10" or "11-20" or "21-100", or
  >   "2@string_match" to read 2 pages starting at string_match.
  >   About 100 lines per page, fewer when lines are very long.

* :toolbox::edit_journal
  > > Edit the journal or add to it.
  > > Either replace matches of an old_string, or
  > > leave old_string empty to append into it.
  > > Attempt exact matches to avoid falling below match tolerance.
  > > Must only match once if using multiple lines to replace.
  > > Pages may be used to scope matches.
  >
  > `m8` `call` `--mob-space` `--md` `m8` `munge` `{{pages}}` `write` `{{old_string|--old}}` `--` `journal.txt` `{{new_string|}}`
  > * new_string string
  >   The text to insert.
  > * old_string? string
  >   The text to replace. Omit to write or append.
  > * pages? string
  >   Page range to scope the matches during replace e.g.
  >   "10-10" or "11-20" or "21-100", or "2@string_match" to
  >   scope within 2 pages starting at string match.

* :toolbox::search_journal
  > > Grep search inside the journal.
  > > Glob descent skips hidden path components unless named explicitly.
  >
  > `m8` `call` `--mob-space` `m8` `munge` `{{pages}}` `scan` `{{regex}}` `journal.txt`
  > * regex string
  >   Regex to search with using a Perl-style pattern (no
  >   backrefs, lookaround, or multi-line matching).
  > * pages? string
  >   Paginate results to browse through many matches e.g. "11-20".

* :toolbox::zork

* :toolbox::read_journal

* :toolbox::edit_journal

* :toolbox::search_journal

* :raising_hand::
  > Hello co-op friend!

* :thought_balloon::**Starting with a greeting**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf4ff0c5908191805c790bcd230517,gAAAAABq30_zSYBqoOzXwAGlpf2rLLMZwVMei83hKPy9mZS2m4TJwf1vOLt_vaGZ42G6CRyGxyB4CJIi5IcRkaatu-a23LASLJT40-V14ptLaHe93x5KMnz2BtXQqn01Iyqtp2CeOQWKfbKGwCxleCIl2sjxgNAeoKROhSMFqUVttlWQh4HgXqf2dSO3yKnp4Q4VZnwz48mCiEHEKoO5XMek4D6Ko3u9SgrJm21acS1bj8r2xVrojimmOYoamS4Os_7pIpJYrEnsJH5uncxEXWFg0OHG4Y5vJnJvtwFBuVnDDLWpx0U_d7cX5pw_K47o-EdGDZrZbNCVAsKjNWdjy7wyFmbt7kOPTbkuZ03M1Pk5J6XZc4b_HPDXqEI-nlYjliJKGf8ZV7K5hLBmI7phSfog1AOuUMFYYMewMz_ZZpSdNHQDzCbSKI8MqpVbcvAquZQvjh2VBvrv5pYF6I4iQ8CHJ5JqSoiQwiNzRGVg407hLEBTeegoycKLrMbiBg3mHwHz5XKIFHay_gRRVthw4ESP0HfZD8zJVmgOKPnRyi7uUZvvj4Sl7INOkgwA9DtTcbzTjQ3h0ajsGglrrBRlIktJS_W0dYSLs1b00x7zVTJjVNcdvZin5oS6deWr4hv1PG62PkUYLTWvcWljV6RCIZCq3EbsMFZyALTQOGUH_Up0vL8LjtCYb-AW6RdD2d4Vf-H-UQe0Yvh5QGl5I2iVnDhyQkWBj7kxC3bD7sm-Oxn7py7m5NPqoOjvbfWmpmjLlDKkkmdxv9DJMM8oWxDiZrYbFS4BW9U84ZHLOyhgSDezUv3RO6BRn2JRI-IoXXKEBi6BAsRvIFBFFkWFehb-ZHsS9TC7QJngHkjEC-4pAxj2GxlMEo8dZCq71O_P2_78yw4Hs01io43DGkG8dS9Y77LcN00eCHuUF_PThKfMz-cK9xLU6Xc14BCNwCibod_rt5O_Zfr2L9rCaYJzv4aEfybLSWX8K3QK9uUD4Yr5qXMt2yw6TRXEECfiwcqhrD_QxgMiDi_Ph3XCS0z5vA9zqHRJGcuGZllOZLVQcd38qrceUgVlC0HAJJNvs1CVqxiff3lbklAG5TFIWzpIVOnUY9w0YX4z2A2rq4NVF1VzsoIdIz2PRZWMk6h9aaiNfsq2_YW3c1fkiDs8BjbsfiLaTHk6hDM3oIGUmtHu2e47px6uDCLWYGV6AKlRSz_3FuaoKUrJ7u297yrqF3yPQJ2CFZrG2bxvWl8YvLAH4Uc20hAzWcMkjHposiufYCnFSiLJ4AgZfupyTq6kSvjKCCj2caUI1piPuiykiFye6GiDtkzk0TekWgZY8Rpw2brVHJL4s0saGb8zUrQ-UccP1EaT6I9sY9grcKqC3X4cowoRP9ADh5gogaAuZ5PDLdGCUofl-JOFtbGXpHpYxOT23Bb7d0ePBLc9d5WnwgkPvTjFkajkjt_oih0xLwEc5DGTkbJGX2AFeiuRzm4ilntJoQcvWMqoTPiAJ5XHtOYV6XihEpMV2Pm3UspjhUCv4_qu8t9IdX_FU50fK6UE2rN9FejYzlVqjkkZwBnG7oMDt75fa87caS3vhzJPtg66DaohZDWPcDf0d7tyuhb_5ibfwxi67NEEJ6006kxBrxbwrsLLVDrq4skdWgVBIkcHJLXog63n1g-4QzJrIs-XqaW43RsXinxNTLXuuwBvM8dM53Rnf6yMfEB4DPU-vCoiC-VLaMPSbCajLHV6dBtHETTGNjS9ULnggVYWI_JXr5IebAyGtXMjDYozgg2oQFK1yDakms_Tov0Cux17jFon`

* :calling::zork,call_dff4cee0ecf34e5cba80d204725b6ec5
  > * command `"look"`

* :scroll::call_dff4cee0ecf34e5cba80d204725b6ec5
  > You are talking to a text adventure story game.
  > Reply with what you want to do, a line at a time.
  > Where a key press is expected, reply with a single character,
  > or one of the placeholders for non-character keys:
  > ↑ ↓ ← → are the cursor keys, ⏎ Return, ⎋ Escape, ⌫ Delete,
  > ① to ⑫ are F1 to F12, and ０ to ９ are the numeric keypad.
  > You may RESTART, but save, restore, and undo are not available.
  > You will be given the status line,
  > and then what the game says.
  > ---
  >      West of House                                                Score: 0  Moves: 0
  >     ZORK I: The Great Underground Empire
  >     Infocom interactive fiction - a fantasy story
  >     Copyright (c) 1981, 1982, 1983, 1984, 1985, 1986 Infocom, Inc. All rights
  >     reserved.
  >     ZORK is a registered trademark of Infocom, Inc.
  >     Release 119 / Serial number 880429
  >
  >     West of House
  >     You are standing in an open field west of a white house, with a boarded front
  >     door.
  >     There is a small mailbox here.
  >
  >     >

* :green_circle::call_dff4cee0ecf34e5cba80d204725b6ec5

* :thought_balloon::**Greeting user, asking goal**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf4ff4f7ec81918b870a3e17163e9c,gAAAAABq30_3T-Rd4nGVTS-SY0Tg7uVZzZbiiJtV74KmD6k2zWGwXHyBFprKHYBQ2qgVy3BZGmL9COo0WSqQ1u28biMG8J7Af8WVDwlDt0o8Zu8e9U6g0jl08Y_96eNl1vv6bMtfsxQyvparMiBCTGvk0VsZj5wDEPGiQyiYYZXyz7T_e8JZUIxsdZygVvNmlmgkG-ZEYWaGcN0Nc_NUsLDc7eM6xe5ZgzMJm0TNS-2oILYDaAIPSiqwiyzsElKSY4zWdaWLVevwPjzFPo_bbQ_kKYqMtUTd10SLGuPI7x_Cv-OMRwHt4LHEXTRlShGGXecANAq9-66hLIWkHkStcJ8lokxAwdzXHNRbZmrc9BWdHjx580TTSkaTS0Cl9VLmED7oC1opPnleazXhI-Qth7XbogVusPukuqyx7tH2nmFiRM4HVY7CrNuHiHgDzY4qgUGkNHZS6A_0i9es6RA18AXG9mXy03Nf6q_q8j2MrxYp9bGk51f0Iv6AYNClYuddIuxK1xPXWB5me7P3IiBFmKYN6-7IDeWNQAPTGYv1DES0YhK-2SZz-gZfXQJtbOwJXXwpm6H3lOFs_S2ipZr-XEGzKI1-FV206MLI2EsH3oJZWWlB3mUfratj5GRet5aWTxcLw63d46CWrT5OtEnE5otvzBjDhgbMm3rCZiJpGNmBk2l5PyN1aQA0QHk_x22VP0enrhT-mz0LiU3ab_iYd6LtbZKGSHoTuko2Vw6hZnfE94g_iiGC-CI_BWeHW6Bx1jhA6wyvIfctlXjcdsXKoA2VLU7NRv5Y7ttTrNb3_BGTO1_Dy7GXKFX9EBsSmBTegMYEh4alpjSgP5cpgxxBE0Ivk02145RdMBeRHFM0hAQgsFNAjvpTzQwmoX_oamhdFf3A88o2yWpG3fjwBtCJhixKKMurpZUekcwhwcg6poj6Uuayh2yFpEUs2qKUAkBMfVV4jxjMKtrbc4OwGO5FAsbiOxc9-2fhjrd_FAmjl_mLsEotmfllO_nb6CLILbM3hD6UwncF9SrXU9pxQQK7mpKFqA9PsHVIKSvhUlRaIKh3CnaLF7MTwqiyzH22TQQI-41HJyGLzBc1hCatavYTylVPwQJfiXXgwmhwAP-TrRplSXhBsZorOaZbYrIdltJ5CVqUa0bR9HUQJFCntfwU17ox57PLDve0T0Lbo8C-VOlsaVCTrSYiUW-29LhxjKkGbl5UXsO-eQcshHepQ80_pGbaPRLzm6KkL4EvIZ0UkhLLefq_EUyqwb_W9LpaK5pm9VgrVT8ba7z6PgJvOa4t8y7BoXnWNuAEsfzUiTEiourr4Z5_S12aCgGb9MugiENW6tzjH-SZINbP-iVBGQuDbN05vtJvccbih-CVB43CEXOp4je6nPFLXn0uVsLSw2RZUQnpDJD26AcjH8awd599C-fJeDqNx9ZedZBACQxM1xUkiP8OrAJyk_07B97IcQhujAEDfIpNqYtwMHCA8zn5vdQIZKX691IeLBH22E71v4SA5EU2Ytn3OQpkNpV-sfyzTuDwtIMLcdPzNznOlMdm3ZM-OxyUfokl8qAhdyO4eDfdgM7Cb8PxAfHCddYXyIcg2wsoshYR51K2ny4URzI0y8A0HjMXKWYR4PXyjU3r9Lx00NIaQJeB9N-wJDU2SfnNEO2p9D4Zwizt78YyBFKR9sopX-Urkm1RnX1IIsJCXLIuxzKUNxP_4M5uW4GLGVosnWESfpZtjbWaiRTW7TYqF3xtBDEdjQ3_YP3syJY3XESLneEiWMR-cV7pq-NFBFgnvcKNyIDGJjNrBUkPbjmBfuhse9jwJxxYAVYa3Ym9RWQhGDvxK8gyZMIbYhczDj_w1Ljai0Yn8dD4T4dP6rB499Om_3CBUoFeQXtpGiKnSG74Mzk4RcMPZCC7Q3LcmvurRECLsMjW9qRQ`

* :calling::zork,call_f38efa0edce04010bb98053c31d50729
  > * command `"open mailbox"`

* :scroll::call_f38efa0edce04010bb98053c31d50729
  >      West of House                                                Score: 0  Moves: 1
  >     Opening the small mailbox reveals a leaflet.
  >
  >     >

* :green_circle::call_f38efa0edce04010bb98053c31d50729

* :robot::
  > Hi! I’m in. We’re west of the house, and opening the mailbox revealed a leaflet. Do you have a particular goal in mind, or shall we explore and aim to collect treasure?

* :raising_hand::
  > Have an explore and see if you can get some basic items.

* :thought_balloon::**Reading the leaflet**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf5013d7d4819180c01226925af21b,gAAAAABq31AVfHS_JlIx5em5o9s0mzsRKREtUKVN1v-fdaAAzm8H9SiGJjkmXDy009SunjTbpLuVGxCxYxI80rMniCBvO-0ymuIKqsOsjw994vDhr3Wl1a_klB1cizRuSozx-MlAxuE27dCzqpW0vWd0QFmd2Cj8yRheTDMvAdZv-cyUw3VBNdF28AugjvFnBtGQqU8L5DZ_K20EdX2-sdE9o7KFun6wIxJ7yUg3mb5xNo73w7_Prs_hHckLVOku4p3ZD6cqNkf2itCqzxPoQmUWOYxzSvUm_lzEXcJ4ip3--tI5Z6JlROjHsKjH6tN_cRQRpSj4sUcARSLgxLH0GFPXvvoQJgxVkz5U-C1jjEO1F44vR301X2WEZrbxdU1ifxyUvFfSZOwuHPq4K1X_7xd3OlV_YZsc3xznUrTX5YBCd_vGMlj1oxYO2b00S_j_DD-hTDKMX1YKoQc90xyY7clkyIg5oA2HzOgNy-frsCcDXt0_B-yz6qxIrXD0lyc0UrI_144j6nkWJNqMYQTmw76PMfi-Q-WmDjwGBnHPtrPbv_SOWCmQc5XF9-ejh0HgIVrMuWzJD7gGeOrs324VkEW_aYZvoabTgA5vO4skyoxqrrsvuvUC0S6fsaQcmD_FF-XB0CNEAtMWdH2n6QZ0WHttErgbv2RaqX0ZIpvLQWhMtKMbbRVfJEASVOSPH87MaDjZ_W1S4bhd0uMS8-_ErOKAZnGVW1mUa0hlVt38TH7hqMzD6YoEPaHKgXemq5uTHH113UwNkIyvel6PRX2SAH09IsWjQQ45MwztUdKFsXHzEU5UG5mMStRrbbfyyONScvaGCMZol2upyiay7l0ONm_Dgi2ASevkLaVdf3m4sCGbyH37S2tWXDPoh4QDxa-Gb0vgnyUQ-g9_9RvpR5tRIUsKkeiIdl2fU9LU93i2m-P7D_nC0f_M46XOCSDy3WH0BuLPG6GOy9kEwXZSe5ME5WP3gEcI0Ex1ntOrhcMZeqprE0WbjEYamCivw6-jf2a6-OW6OU2kfOZnrCuUeyVA0yqRZRnIEbTRX4eUmcwlX6SQqXzKXAct6GboxO_TUejNkOF8pzI7khfby4Thkn6HyPJfW0MPbJ2QvW9s1bGzlT3yIF-N0A9B7FQrWU53uJ8GM1vPu-QwHJv04Dg5wsBen91O-j98Fgl5ejePpIVo4gTcyvj40quCYS4PV-Wdm2kRPVi48HXO95LNdW_RrUz8FntRIOF5fl3B4UqhwKtR_o6hKglOvjtALn2a6h5dHZ1bapNPhkwzAMP3VWS0vDwGIjjM5RUpVM07wtQUmD9Um1OcpveEAjzYk-tJ5PAeNqq9niS6UO8XSNE2pcM5U8sgZUdV9hnRCPaioPj9Za6eXqh516uu7mJQx0z2WuZoijc_taA27p4qWsmf0Oy0ylQjKTPZ5tcAV2XW9QxluD2eLGy8ghA3pZdmasuOA_1XpjOh2gb1jBt82IySIj0B-Dqg7hq3zyN2fGNPE6mn-fjjmCAONA5SCmFYsQc2ZTZXmUiB6qNJhgIAvfG_V9PM7lJ3I3gdoDp2PXN5eJ1wcrIkimIyX1ZPjfbjiFmsZs-tTg18Q44e_WQOKeOGZqCcEbeCTQqMhRK9wsw_QKNISrZrir0fQRRELRpIy1DsMjUwrkEvWVWlrxr6GIeB`

* :calling::zork,call_e6d854cbcc404d5cbf4d48e4bdfe0a7e
  > * command `"take leaflet"`

* :scroll::call_e6d854cbcc404d5cbf4d48e4bdfe0a7e
  >      West of House                                                Score: 0  Moves: 2
  >     Taken.
  >
  >     >

* :green_circle::call_e6d854cbcc404d5cbf4d48e4bdfe0a7e

* :calling::zork,call_f9f0567365c143e28422b855cdd1d488
  > * command `"read leaflet"`

* :scroll::call_f9f0567365c143e28422b855cdd1d488
  >      West of House                                                Score: 0  Moves: 3
  >     "WELCOME TO ZORK!
  >
  >     ZORK is a game of adventure, danger, and low cunning. In it you will explore
  >     some of the most amazing territory ever seen by mortals. No computer should be
  >     without one!"
  >
  >     >

* :green_circle::call_f9f0567365c143e28422b855cdd1d488

* :thought_balloon::**Exploring the house**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf501e413081918711f0d4f16ea31d,gAAAAABq31Af7mvF_K8kX4sagzsd3vPqeHzhLryHSZhou2dkpeEMcMpra6zKu6DGrb89QZspL_BUcRFnVCgjbT1PjIUEPtBNlxopXk4MrWfyH78KUPLm2LvUVJMRaUG--9sNjYjKXgsDW--_HGOS7sj-17xUedjmFRcgCN6trdzHE62XCEbX9F5TrLgXaniEoDCEtMo7HL_plO-qGwVpw8dS5m-8OIAdHlvHiDPq9PNwfM-mSoJWDkMrgHfJxRk9WksTMxPh-0EHoyH_o5utqTOfrnOGjbBZ08ZN2xKuVrnOD609ffjFOwxv8wBiY3nvdbsnuux-fPI3G110oT9rcYIpTP3tbLcgJoDy0C0K7HxF7h2y_QT0jqHSq3joYf7sYaTsAcXK0HZthHkeetCKnsoMBVzcS5UL3b32Al4jZ1jx8Hr81PnDHCzy6jqeX9LA5JdwZjUMYjVtAvvk0vGM9xDp2IvfPnLYqTtX_F_Wr69SFuRnaMSUcaxtXSR0e67URd4ZmEqXzoghSP0tFxQWPrZMjmV5mCxYD4wGj1BiKVgcL08O0TilYXpXZSTuJZ6ylh_lu5op2GqqAgOMD2Qa4DqFmpIQhGghMimGpbg9FvUBgIcm7TV_lc3z38_-6OGJVlOyJ6VvnIcW8Tw1s5IbCeAMi1aqfm9ut9uBJFa04iJPZ6M8gMIOesFkB8mVadIMoL83g2KURSbNKAQt51aflod9uIXwAlDlCGYYymohYMJXLqrhpvFRnSiBkDWnr8ONMFDUKsOxlLz-GuMBycg2iHUmt3L4udYbfwfHWRsGWXftKYCCT7Ij-rSi38q4ebTrvw2DdB6vGIfqF8Kp2NlVj_oVhBQU0XhvWUz9xIvrmHYQDIHU_URZm-RsW0gX0Lqz6YRUjhMRNXCjRn-qxLIgZxHk9mL3qMvjejT5HiHYHxaaHrZCOC6Op0TDay2lEbD0NuSoodMjsWs4XenZpb5VRaaf_tdUYRzhrZSNMtFPm3XCuulP_Lox231_8K19Rds4HDJeJ-mdM_7bmVRWd7S4JSixRbWZ_qQdsjLxVtxp-Gn8t1IawuTL36PfIdrOLnM0-bhEPZVlBbMAtGHQNf6z4DLIS6ll26gvEPzxyjJ3pBpCREXuj2tkIz4rRFSaKXVf85Sz6Kph2HVwUbjsqtTDL8iMCVtIh9m8oSpX12DPhvJlegnDtr4XswI8Tg6njD0pUoGW3Q3ZfpbbomucH7G6kY3pAIDhtLq3VxNTk-2HhqNM-u_EJ8uoOjad6-9E-uU0kb8Pd1CZRofIvAB9lLdcSEPNVZqCqQCVqfcevkOFHiy0zmT7XqNZmBsJzH5YsC7uiUSuUu7_XOMEvfz4-nDDvZy_s_Tw9XItq6k8Gl1UIDJfTUa1BKhMY5u0F0Qqm0YgMIYoa8c3MPBWDhW8u3FqUY2IXSAojPHsIfKAGjGm50UXHFLGSb0e3wmUAAGUYamLBODs5VD2Sj-9bs4y4a5t89ZrGu49fN5jYx4lg5NSOhNfZZag7j-cr3mPreABHZMCpDxAr-MGTh60YZHTz5tuANHVYH9LOJw3cIzuYLUSYfmtCv6VS46JwCTU25J5IFK5CQrL-DzmxwykIh4Ubt7joB_3PUjrjdYfw0U9h9bSuWdBCApGiga12VIjzWM14cwZpUNVp_8RKKMN34mkgYqXnx2DWpINkC2N3g==`

* :calling::zork,call_1afdd02b21c74883844b530552e665fe
  > * command `"north"`

* :scroll::call_1afdd02b21c74883844b530552e665fe
  >      North of House                                               Score: 0  Moves: 4
  >     North of House
  >     You are facing the north side of a white house. There is no door here, and all
  >     the windows are boarded up. To the north a narrow path winds through the trees.
  >
  >     >

* :green_circle::call_1afdd02b21c74883844b530552e665fe

* :calling::zork,call_1605c87cb182411487fdc6559481ab14
  > * command `"east"`

* :scroll::call_1605c87cb182411487fdc6559481ab14
  >      Behind House                                                 Score: 0  Moves: 5
  >     Behind House
  >     You are behind the white house. A path leads into the forest to the east. In one
  >     corner of the house there is a small window which is slightly ajar.
  >
  >     >

* :green_circle::call_1605c87cb182411487fdc6559481ab14

* :thought_balloon::**Opening window**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf5026f8508191a25f79473f593394,gAAAAABq31An7T7F_Bdki-ygsyDKJPdC560scbIbupl6BhVbEfB23ZdvefRPgGFVLCrMLdlWPjU7ddzlOM7ClZId8kHV9o7iM5d0QcnSxKvqzJ3rJZodyxxIJ69Pu32rLF-k1Nc50P6DUYYzQ2iahhSh-AWewfOMVfbKsrTdNupwzmW0nIg71cSRY5uu8SmDzqHozGdg5gJ4KGaz9QyTmsrQiaipc68B07CoY0zeqSgsgGex5Jt-YubhDMQ0EimiUl7o38tX6Zsa9XaMTQwLMA-V6F0ewUH8CCdHRNByry38jzq8jwABkiNMdn7MOkXQiW8OqRNTucn5SLJrC31eZdmE4rC9famGzarbItwedyt8vjnnauxrBExywATjsrcNdsMgZmSill1PVW2iGXr4bBHH1-azYOsBC9y8oCgnOFDeIj3oq9vOLLctmhWSrl3FlytXqJ7VYHdy20AUbDlXpfb2KVWSoimJBowfVyaezWOn2HC05oqtQyLnsLjYG9LLeSkBz4X3_BVyjKcgQt2uC1hWfxfnn6NEp3If5o-97XuTfBPZi0kuExLMJUOGyKivGiDrNzdC741ZaJa6DkNpVlN-hUB04a5gjoaXZcsZTCjlL_LctPDWPOFRUyo9WLoaQHiUc0E-RxxCHD4OH7AmmT--HT8wG1z25y4D09ElC3UulSRNtpLYiADavv_utMlj9l8Wz2lCnN20CFB5xMskC6i0Ml1x2SW11yJLFCGyfgeNWOJ0cyrq5bRDsFYxOMyfaqZyGYH9ZPVHJvP44jWv7tIvXr1EcMOW9JCdgBtJK_r9WxZoZztuWrTIaqZCxKUA5KgOgpBKcSBx2JjahDToMXIgjAT4CkbL6zjT9N47PW5EFxvk2xVxvXgZirIMvd_7aQK7oysG5UkYpdFY_dE6snG2RjkL4zWZs2JzRE5CJuKT0UCwr-9rP3ARaMi0XGsZUbHTBc_P6onTnCWCmrAiuJ5a1Ve4K6k9mL3giPijZsO5de89n9ZpV1jeMDjWlS9lE7XjNMooOEEvUb8k7TZPpfTCK1tElp0ggU_KBq3PQ01Ec7dYZiEJ3Cgh4rLCBxU7LxAN9Ven3klVA3dSojPON9wiG0kItVLm48jcd4eMnzcBbMttke1Lp4EXC7lD7SN3-x01Z3KYPq04qmnKMQMjz_0wAkOVTsMiBEatVCK8o8FZZ1ItuljAxUFv00dMiEPp_mqxA1aqDXKvslt-NJVhD3w5d0YJoJDxqGm20UchOCfnVkvAloK4cCdqqYDwsA1rZGFoi7jAZdVDAd3l9SDh3Zg6Q5pZSaZIXD25FdWvnMrvuqUTzB1kRnvhloC2ntHRVypNTQn8r8Q-FDr1JiNvtMmC1Km5Hvy66vfMKjFYDe9F1-KyBsL6KihWQwqOk1hn-RvYSCqmBINjABa4JCFRwh-FeZoruABElvQkTxMW2ss-qZG3QJXwiUdSYxPA80uAQoRWESkI7CT5t_hHl2o1HgflyTupyV_r3U0_JEFrtQ-_HPfAdms0V0XiCi0w_Oue9dflB2qxcsnNWbzSPGCTo0sgfONVn923EWpR_q2rChrORw_waHfMQxE=`

* :calling::zork,call_f3011509cbaa4470870a48e56da4e940
  > * command `"open window"`

* :scroll::call_f3011509cbaa4470870a48e56da4e940
  >      Behind House                                                 Score: 0  Moves: 6
  >     With great effort, you open the window far enough to allow entry.
  >
  >     >

* :green_circle::call_f3011509cbaa4470870a48e56da4e940

* :calling::zork,call_67d6ed4c4e69402997c164063ead3e58
  > * command `"enter window"`

* :scroll::call_67d6ed4c4e69402997c164063ead3e58
  >      Kitchen                                                     Score: 10  Moves: 7
  >     Kitchen
  >     You are in the kitchen of the white house. A table seems to have been used
  >     recently for the preparation of food. A passage leads to the west and a dark
  >     staircase can be seen leading upward. A dark chimney leads down and to the east
  >     is a small window which is open.
  >     A bottle is sitting on the table.
  >     The glass bottle contains:
  >       A quantity of water
  >     On the table is an elongated brown sack, smelling of hot peppers.
  >
  >     >

* :green_circle::call_67d6ed4c4e69402997c164063ead3e58

* :thought_balloon::**Getting bottle or sack**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf502f66048191930f27342700e1e2,gAAAAABq31AxyJ1gM5GzsxgTwtHhAfuotoJiRZnbtn8uzsL4yLuNXDrX2Ow1MPDrtjz-zmIHv94k9L_tpA55xwJNuAySLXRsGbCxTmtTjptVDIzwI0pDYpiUML_fLMzjo_zZNFkXlk1kdlRH-04woez8x5AyrolVMyaPkoOo8-40afHwz-diHeJoFxGvwv6hxkND6irUtQmypStzKPl_1OfyPV8bjSCwM9yzjtUovnXCby9GrNw-cr0lU2Wrnbhd46epx5vteH0-MnF3T3b8bF4z-mI_Ad_yumnIT7wUME2MYckg1HF5v3ch5eWvcSdvujOS7em_CeXyDUZF8JcsRyAHWaOKP8uuEhwyKmARvy0Nc7ZlA8IIOjPnLVFf9IPJPAqa8J9udHbjCxL1H8bWUdvSrz4g0KEdhors9vOXVUb4qWb1gdfyei8FJuj6IrggfN2iN7SkXaai2BxGIi3pm_j0ocS_lDrz5BXtoB5mofIIfxPI9yXvk7WM6gMXs2u7Jqjy4-xZOzAWvSpJAt04j197SKppfMup5Kyb9eHEwzOrKuae83cwZryb8z9NGXw9EADG7VVDKLXUW4EhUhQ9eGgCJIJ3R3D5tqylfsY-IbDrrdQoWfi0QjPIqEKA26Wp1YpuDp3uXwnbcIoie_1H5cmQpmbzmDq5Q1Cx4IXT38b6dQJpW459VFHGI_EpayyO68k4FY55mXR73EYu4lOntAXDo-LM0xHWWLyJZNLHm5iMKJGyV2gRjYht2xpaox629QTqdH2FjzxN-Wsm7JaD3aWKo0Qj19N9ZqDraOTcx8VdfP2RYQMaLGUAchDExVtWpyi6ckYDa4FN2CWzfDCq_DijyOJ5fo9sMboDbRN5Z1tcGqMud6Zuy2LVz-2-03TcRt1B3JYMemNBWAN-tnVnsvqZgAqKrBP5I7Qoo3jElYspgnyWL2obzDYu6ufPkgFBZ1SPn-QUSNj5zCH80gdJvYCDWwsH46xIROpAb0X42ddpukmh5Fj9OO-6TMNyC0s4BvbX8hSb-VBx8cbYPDOiLFY0Qt7Qz6tECthjACpx6RxwbPFBgTrD_051xL9UtoQ3gsYciw-T6B-vHNy7TiQT35lS4wzK2wHVPUYeTizUIx-AKP26O8lpw509-TkoW9OEvvkDnHYt72XU_LdIUxZfM9_Udzc2FOyobuq-QWpbEArgyRV9lZ8A1MGpuVGsup8I3AF_kIaHv-nr002_wNBfPSe6CiH6n0FEE7gCWw55G4Dql-R5ZC8o3uFtmz69ulpdYhE97TrHNLEHLhXl7FS5-R1-8sgGn8k4-CPl9NnpMWooeY5UqYxkfbW18b9XPdW4mecDz24PwgXldksx3jAOK1TPU4LUAb8YwDbSlk1QxnZdjFtinFkqFRtZPuNpbXD6NGnlcHCtitR2zhGmTSuYyoZ5x8iGeLfTXTp5VNQQQkuB3EOunboWtUca_Q8-N3RIV2Y7tFL4Eja6Q69uJ9sshAVhKnnqCBLBxU5bnMbFSUVp9GhnL0bmO65YvpxsUsdCdg7iD5Ga7jXKdYwg0brIET9OE8KXd6VJfZpc9JDGoOLHlWFvyQMDYyMK-x5SSXR_xWHwzwlWMO29RzJvhlddQ0Ec3KK1IsMjMCsEYFHUPj82lnqE2dkhykc=`

* :calling::zork,call_28c7b0b456d24adb82271574ea327259
  > * command `"take bottle"`

* :scroll::call_28c7b0b456d24adb82271574ea327259
  >      Kitchen                                                     Score: 10  Moves: 8
  >     Taken.
  >
  >     >

* :green_circle::call_28c7b0b456d24adb82271574ea327259

* :calling::zork,call_ed75104763d84d189523c02a1a6536fc
  > * command `"take sack"`

* :scroll::call_ed75104763d84d189523c02a1a6536fc
  >      Kitchen                                                     Score: 10  Moves: 9
  >     Taken.
  >
  >     >

* :green_circle::call_ed75104763d84d189523c02a1a6536fc

* :thought_balloon::**Exploring for sword lantern**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf5037bd9c8191a6950c9cfd9b89d3,gAAAAABq31A5QnPGEItQzPc80cR6CfF5ng8Sg8qTVUJpTb2C-5khkBBuPuPWrnAoVsfj_GKoAbEdaCSM7R-BmwYdFhBE1vW79PrrVayE6gGUl8O7bbI7nWbrkiQ1NoiSXvsuW0-fgZT98F3TFp190LppdAzoghwbbjCP9CxU8hbgP6ChGQq1mvo5zatB0X__vm_BEQ0qVqmgroFUoLx64W-pgD2kwM4v9D4W3IbwJJz1_hx96VFthdy2CNzbkKZzLAoxYilkad0VEbazSIoWi10a6IETbj13j5aHVfYnHoV4yyKrYeRMy6K2BJzJDnYgl7gPC9wq3pm1SBcXpnUnSvXuMxYZwmIUYM55_OAY2bBuneOpW4uh9Nb8noJwexWdQG9NuLyfDrHrL4uiV5tVzjfTUeU5dUb-25UWOe3yayh2JAb4oYULv7nABnTnAVIxF0KNtAQ-NDvXDqPX8fg_9y24A-BDolC2YMekMs0G26QbdEGgoldwHNGqFWVhkET6i7R4AX_6w-VkTx2sOI55GJ7KFk-Nw_OKp8eo4mw9I9EQTFHOGE4c7ss6KhvnYR06zMQSaX38n0wuanZ2R5A0VgxGz5RcshKqlBAm8GZXvrII8GbifhLE15modZoJUcmlyE9Y1iL0nLdUzvsN-zy8GA14dh6ns9eZL-tcwUb2yKx1Kez0m05wFe-wBIlFdf9JjMfy8KNt5mgA1DHYTrHUKhvcAz-gpUPuLq3buWclmSbo89gkcqGzb6T7EQhgmpvEq7kFQcbdTK6_YM6TCrQHRSq0nfItyoJCx-hUl0qQOiAayZVGV4creDCtKXxgBYvs_qsJe4KQwrG2tE74Mql9VQKlgMk_LQhZvCKhgP8sGmSuebkyWZUGLBKPD7sfM5NZzPld-K4kMcPC3EI7YSlnhxMe6-CM4-zBXV8g3Kufph5bo3WthKtT9WbWinDfAvxRyyVMX8ataGZhUC5Y3aFVZw1fNbP1S4aJs8NsUZOB2QEKCrkATRuc8QDLcFJpn9u29aYv8Q-IBw32R8dbpsbnG9uZUnQbzYQHE-gZkcBJu5GDOlnafxw4vS6vHWeamLZoNCPNy0F4X-p-Ggx4CLzdLFonPZQPEWre-j5shlxDl7rT9fTiJeqfYt6CWWLE6w4W2CyZ7C6F56JOBaVWmQ2wFPuk1HAYqEYLl8jB6iXRqo6xM6CcvbCsCNEyYk8QfnUBZ5FswjavMTCDjtFCWnfr4t8jW6joelyIfraVLUw8TEAN6Aacd45tZkYFevBKNwJuHPpOkmPCpJnwz7bdbLkS7U0mraKvq_q_7VIVua5zSuWgHJGLC-LvacCgq0cS-EVfEjP0Zt5ieDMcWcKbBRGKXbEsN8q10kJxyCD7OJx5GE_sgLt8CgjHC-OKHJ4ryI5jDHu3V3vjyq5XFevx57XXRfioe9m-OnFzO1yyjxCDoSbVgdT4OLvIa8JlAIM_K_9B_x-nVedhUoFDOLzzBZnwKHU3dH098jK7151lSztRvcx7qh1YdzTHS81rs8fBIgafomYLzhNbzLFvOE-OlCO1oxoJLOGJG9qrmKzlb6gLs3xJm5SU7W8iBTkWJw1v1V1ZeJ24WrcmIK9MesmMnfM_JOF5S_I3dVT-Lxut2E0QBR6Ke4rdJa5LTKQNTyR5qECBzdyemiuP2ybDLgrOUQpTeZXzeKtHtTOa-Q==`

* :calling::zork,call_e97070db9a2f44d29111f1a14226ec44
  > * command `"west"`

* :scroll::call_e97070db9a2f44d29111f1a14226ec44
  >      Living Room                                                Score: 10  Moves: 10
  >     Living Room
  >     You are in the living room. There is a doorway to the east, a wooden door with
  >     strange gothic lettering to the west, which appears to be nailed shut, a trophy
  >     case, and a large oriental rug in the center of the room.
  >     Above the trophy case hangs an elvish sword of great antiquity.
  >     A battery-powered brass lantern is on the trophy case.
  >
  >     >

* :green_circle::call_e97070db9a2f44d29111f1a14226ec44

* :thought_balloon::**Taking sword and lantern**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf503be5888191bd47d003fffe7167,gAAAAABq31A-4hvWy0NVl6Gj9LY6foCMOcbCqwktSW3aZxpTYUBdJg-1ENTrZzzyE5U7lrUYvlpzBNBuIY5L6GjeMy4gm3Vfssy_tkCtJGhcBqDcK7tnSqFtzF7CNj3XqfRuMiQRVLKFlvniapt-mTxVO2MARGqfyNFAnA8gCCqf-_8xjtQ8viXmFbJOasPLL5-RQvUfeoWwjcXA948-8pDx2pECVcV1FiflHS7lREWSDvg8SfXdswiFIrHbz1sM5DiqObELkic0OlMYJAwttu7UDbDif_QbcnSqxhXM1w1koFyKaR1XNbGNwI_ntarB9__oB2pwC-mWWM6ChmDBlxlf-8-PA9WWadsFUku526Rbeb3yKv1PWgUkx2MfidJcL_kz3bIgY0gK7hWn8ybnHUqWNOHG0dUwlxmNFEnMjkdfTFeu2tk1BID_sd5qnSxjIs2hCpv0qzVGj8ieglGN7tItnHMcu3C9qnJEr5LW4MXYxnRNHi4kzMfWS3cd6jlWmBxGulW8cpTp8CtKlTqIqkGI_SVdkd1fNBJAf1fOh4ZlIHGgUm8oEOOW68rdDEGYur1atTBqIOBbELkmYu0L-w24zpDLb6Z0UgVxzOkhLm3vBcVCB7i2xiuWnjBdkyLb3jM4QJHjD-zmRmKhkWYXYTa-Olhc3YyNpOKoyhvIqZ79BYi-uWxDvSlAyM_zuOCuDlr1NvcJ03e7-NnDkqS_VnQYhWuGoCa5tHRfS84d7AJW4Gm0-ZdEKKbiPYjWL0DY7g4sbUPlqKUfJDoikgF-Kin8n2yJkony5wW-fn59DjQtRY8PUsEHbW3XRcdBcrqf_ET9n0nw8NRq5t-SDI3CURmOBI9gjMY_WtwY_UeYuwH2k84ha1ROQyMZzw77pR_mJ93bH0Bgw8GuQD8Rn8kBMvyQj-_04xgIVgQlZbRFbH8l8ANep89F6yY16WmgADdAgRKyYAxXCTmV_BDoviVvz-4YrZc0BEOi1sBBZEmGsvelwwCT1cziMzzzj_B1CVfvVfGx9nJKMBV15CCziXp9KRHDxsViTlPuTNNOK0B7kciTuuVL7ymOYlmQktt7IyL8fUe1ZUUSvfmbimp2aDngOJ0KuF-TyoEAkfN2j8B-kpy1JFtHxJ-ZO2wecCbMj6dT8WK-3vchBC93ziuuKm_9FLJhLU46pMgUB2Y2ZTvhXM1NNcn3b8C-z4Ocnnj1rEHoplewJ1YUmpLIPKN9JUDzkFBxPJaMJRuQoytTSTXrYrmVu0QFQXBj1DRUw2PPHflqKekeiPcn3mI5zrXC8eP_QYTVM7El6VWjZX0RjOBqyLK-gOfbwhHP-Yg-0jW5zm92AzS-3P8yt9Ppt-KxSdTeyG4HLbXQl-TQrh5gloi2OMdHZG3ylgDRtdlPA6O35nPq-aM246q2QvX5eA9qryTY8tBf5-fkquwXikQGGxNfPQXcSRp5XblvxAiTfh69Ognpkpy754Hh2x4Lz7vad2MiB1h_melFpBWUfWM3ajtVrighPnfyeWHfdHTGva8wpCxt1y4KYqmW7KxhR475iioitEB2eKnq0XCpY-XY0Qlv4TRRAcVLIjkMTXfF9IFxVSBacLVC-lAdmCkaRvFUkzpH_uyaLzfdeaRR7LHWwAx2omrXb8xMDmeHcxUGlUF_azkICaSyFd7ICAXteXoasmdj5PeNG2LEXm5Qpw==`

* :calling::zork,call_40b540c666174f98a40df96df96a1fb9
  > * command `"take sword"`

* :scroll::call_40b540c666174f98a40df96df96a1fb9
  >      Living Room                                                Score: 10  Moves: 11
  >     Taken.
  >
  >     >

* :green_circle::call_40b540c666174f98a40df96df96a1fb9

* :calling::zork,call_28adf7900e404f41aef012efbcf11254
  > * command `"take lantern"`

* :scroll::call_28adf7900e404f41aef012efbcf11254
  >      Living Room                                                Score: 10  Moves: 12
  >     Taken.
  >
  >     >

* :green_circle::call_28adf7900e404f41aef012efbcf11254

* :thought_balloon::**Examining rug trapdoor**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf504a49fc8191b03f395f2d46a793,gAAAAABq31BLWUUALGlGsy72Flumyca14AU99HT8tkyIDQv6eZuxrPlOjD1L1LVq8bbRkpPiYiQ5dHC1LHOGMDg6RVEO20WM0tG7oE1LctQIxWHjhuKS1ExSk74Qd3U-_TRrBu6wWXvhWy-4I2J754wy8tL-w_BkQWl_Ap1OPbqvY-AVrfXiL3r2qE2ZVtwMmp6yCOKciR6Cc6tKgFSvdmuQ58iPDWbfC6Zpg1ql7mn5b9ULvZ4bZe6p4T6DGXKcQyeiRT1XV3PXXXZWBpLr1GgfFXThqx103pLzAfz8tjSb8Msg4ldY9SwVOybezqt2ZTf8FDtMxk1pkhXNq91W_K9mIt3W6Gp63CNY9QgmstCf_9n4jYxG2mA_LilKPnAYreIsQ9U2xE5I6dAYF2ikZZ4qjV1d-piV1fJhtII6c6zk_kNJTkknvbABJ4tXFVEHcrWdDkb_5POT-DRnVaRkIAONkkfZjNkeRI51hznCHUIO2RL-fn57Z9Kvj1hBqryI63t1Zl4J1wTAqfF6kCpbzP3ulrr7D7R4UAvTeCI1c8IgCNp3icrOaoMusAz7nEpyXhWa5zrrWOlaCykax72XUclEGllg6GElsV6Pi3RKNcWzzeAh6vYQJ_3IoronATFUmQxeIW4vOxTsR4JQnVqMQw8r8NhYVH1BwdFeARwASnI1T4MIaq-zKM6NYRcWjn1IrvL3skL60tdV_0es-k8cacf7dCldi8uA9SrdIs1rl8U0iLWzG4fleAHE-P-hqxvMbNm2oyG0RarI0mnDBS6ZWgxRGaLY29xZnZTXQqESCtQf-cmXlVXC9D-YZIFJIZOi_yfT7A0XGdpWk-d3kMYvm-4o8x4ddjdDyalG9yLnVBfZEy8w6twzNjIrZ6iuh1iADw_GGSp8Na05RXRf4s6kZXpt5C-lVHtIrI-S5oG9eaAd6c7LLQ-qkAK1o0SifMOyPn-VQpru-jxbyia4Ums0ktVP9aSFzHcVM3rwsYpW-C7r6MGsTL35Op2gf8VpbkLZAVP8jra8QhF2RHfCyr838p02sHBOWmoNcnpvqCHIKQJekfeIShFosWwlX-SY9xYkZOTDPlEW0m2c9zrltCk2WKtly3ZX0xZ43Sw22u3XILGL6JAoArr9sqgVRuGkBTAC0LvREpUWKoYCLg8NXOAcAS4XX7wwl6N0nb6cSOqb4zRecR6SJydSNK71UufRbVB-s9DVx4oMVoFLm2h0q5gj-77XBsyBV9u--fYcoHq_p5pV2NdKKa91oF3596Dif3WMS9rCmbHODHf5cjJT-BWUc1Sc0jVmqRHwtV3LLnxvCxTDv_UkkXMl7GR6HhIYmrL93avSDn_ezgtXOZWJSUV6RSw3Y5JlQrRC6E6Fh2qSPXHn8YLuehC1CVbsOBnzm-aqDlvIJOo0yU4IFOpf99poqSES0do_5jTAzpnI-3EWQJmcJi9JhUS8yYXtIsfkiWng_-hMvk_k68Q5AX78Uh2onFyCPXXey7bJnFrU4Zm-JTAnJ1At1uu74-t2dQQlaB2HYXr9MuwjEv0yKnArETwMZytNyorFjZe-PP06EN11J_jR2OJtH57LE6HO1AU7ot1964ElPNgwWA58D1zfg-2JDCaJlXPnSio7wkHO4pmBEa3Pk7DakdYi9Qs=`

* :calling::zork,call_9c695aecbdea47cab98d370020116ebf
  > * command `"move rug"`

* :scroll::call_9c695aecbdea47cab98d370020116ebf
  >      Living Room                                                Score: 10  Moves: 13
  >     With a great effort, the rug is moved to one side of the room, revealing the
  >     dusty cover of a closed trap door.
  >
  >     >

* :green_circle::call_9c695aecbdea47cab98d370020116ebf

* :thought_balloon::**Checking inventory**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf504e2ccc81918993b48c2716831a,gAAAAABq31BPe2PuyhdvV7oYh78Rq2eiNSQvxeho_tpwmogGROgpu4m1q6akWbMVb1zePz2fis3ooBQl0qttA12ezvovByrbZ7c5aW6umHAo9kiSOBF-SEFPnXEFul-M1KptUmc-VL0w2ywmmhQZf6kLjAp5GZlXbYW34GvpWxlP1kNmaIvqrAdVDg7VZz-WAUi9Zd6Xztt7YMk2l5yTzKkusrMK8j76jBy4Lv5ZP5Owh7IZdLmhldW-6eLW9E2B9OrsnFT9E-BW6PhpSCYY__6lIpaBu0BAJ42DFW3TceTLHC9_R2nFOLmx0jz827Osj8A6p2XR6AMErquqUqXX8OpwrkjxnZndi7xP0JSDnZW756OBZ8Y3-tJ1BYegr-I9jSGAXu1gozddWZW_h6mjB4uG1y6S-JaCD6oGjlV1JwAaVa4qh2KF-3oKR6zLiCeHjC9JtArFmPvGFv_rz0aEcAcfErUQ-vDzqQLKEn2mV5Rq0qoRhuVnDGqEfJGX4e6WHev3WLsvJrUUMhCCsSOgzsSHTQElzjkfVVjtrYugj4qXX63t1AS6NEjqtyKry618jRDLWRq48cvsdx-rM7ESGa542DQwiEQBXYpC9pfwvygNyOFfB3L3GLnMIYsuUNG9p6FGz0dCEgOVzr6Hy2mYeXNS2LVAvEERNfSvIGSQ0hlEa7dfXdHCr_n2l4sGCvc585WsG7dJb5vrQniDoLa7-h6rHWy0iILpz6kEAL61R0D73FKj7lhWGqc-s0hU0_P8RkVixjITZ3c-5_USsBJHsr2SXkCtHhdtZF0ocxwF8gVcfuNM0hegnmIpZOLfo_wNNPUKa0yfksRm2ZS1zBU3Gg2XuBkvKRqoNW3s26l34hbDVRd820qmZAYOjEAWXa6GHYLl4b6wYQmnmpTGBDXWi477Agw0_HmWRA8P898EEa6MIm3ry_X58MM3Hf2uip_l4e_pV6Z5w5ag5eLikoHfy08KjqWRBBby_24kU3HFPhXPkwd1L6F796QIT8zknZ2wt-VZqthLOtBwH9mTyshDTIyQfLjbmZnLk-fCKLysz-UnKPu_nMyifmUkIdtnAorPqLzHI1WTf39gvi0cP9X26_jcmZ9pcD4x1nRSrOB7Y3qwPG0aop0vhZes77CF6CQ6aaxw_CI7I25jvRZKR_l7rZKsrQQRt3WP7ts-9duqjQKXO74VJrkAfaSNoYVVFJWIL8qjmnhF6zoP21RMsdvegZdbHu8xHXXMBFp9QdXXKt2UQmBajI4adqw2un-TPWXGX3fLAUuAPGKTjPWftGh6-F-NPkynaCQ2Uy1xEK4Dd9Tcpc0zmNscituCJ5i1rCnxPNXEyhNzoyYYMHwCOD3XWAFiiO4mKu-EmzjSUiWRM6wUs-Ns0BAYmqVQw_inRlSiGSyh-yzacjj9QDBwufcB4s9dmRzzdnxeiYrpERX9ZhpAs-hXamlzf7GITK5SDI6MRnoFU5QupjiFhH3sYHsbRSXFLhkJhOEXnWyZRwzG7mxIyblZ3h5tXWd1388eRH4eaf-B9kix9Ko-e-JO1VqQOOVAw5hpIC4jksdL1J-znwIc_G1DlMoElbBysyIdE2otL0eKM5st0u4UZ9Nv3HoApe-qeUJzMlTMj-bycI9Dqu5XVELGN1DfGB03SdU71HTl9Bz01dARgVWgHvLwlrq2bRbiKlI-CqfyngZzLW_K66nV-uqgPCikEe1LqvSiUpQBTlgyZG8ggyBnET16A3uGLgQd6T91Ij4YvT-DV3NH09N2bJuvo4QWZ6bf0rxmRZTi0gn17etedbTBC320BeBhJX-QNxduf27zU5HnN_tr1NDUVjzYSHJk01M=`

* :calling::zork,call_6eb309c45b5a4f91a6361ecad3895539
  > * command `"open trap door"`

* :scroll::call_6eb309c45b5a4f91a6361ecad3895539
  >      Living Room                                                Score: 10  Moves: 14
  >     The door reluctantly opens to reveal a rickety staircase descending into
  >     darkness.
  >
  >     >

* :green_circle::call_6eb309c45b5a4f91a6361ecad3895539

* :thought_balloon::**Lighting the lantern**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf5052c94c81919ee13ae156634dca,gAAAAABq31BUU2r2zspmEQyyaTPCaTWxPMnVFw8ctI-W_un12TsPVL7Gw5QOwsa2Ra_QRsHeaRBXjeSzf1Sg-7trNQzasyLfUACrjNZrgubm8akbeK5RBtI3wM-d97u_bY8Mx0EN7E43ZnLd0aBwdnt6SWqvHAffF_RarLLwob7Hm1oY9tg7JfOD5HGfd8ezx0o5NnCyoJRGsY6gCycTl_m2krYn8jb1fTdEou5uZjCGjQQQtRL1zn9VRxJb_2XyGzCS2MGmbTxFq7HkvZXFAJmutduCnLakWIuWjyb350ZuDVFuSabFr0eoepBg0_jUehZEZ0CgN3g_JAoEKOq5ZE8U-S1GxSi4YQNhnjh_v_jYuNrXAEzcFJYHrglOpjAllfqQk9vZ0W6llQfE0QoFlC0BH9ShjKS-mSgtw8CFJaIDnLLUGLZYGNj8YCeylHzGdJAxvkxonRjtWxKXeGSEAi1FPwJP1XQ0DUEwuA31BsM2e669rvvJ9R4xo7_fBrye3IOV16u3LDqjWo7NnZIEY8rvoh9Ny0HPpZyaSZIoR0hhm45UJtsbuPdfvihZCkayF8_pq-i25bo0UxHKifRXB_YaMRsQHR9p0sVNIYJSKyepv8qrotbZ9GGDmKw8nnmUTWC_bl9NflHgno8JuT3cBkJXjJEvZ5Mwi8Ak-AVhg9XtUMggf9GpgOdQHHdpZ4VvLxrwRx0Ee5kmVjz8kZmhOikZN9xujdjuUj1YBWfm56sRH3vzva4sR73Z7d6rHrgoEq80x3tP522zsMwlLw3s_822tbfSQ7QW9MssIZyI-yd7wsoaIMuQEnrCW0HwYP_lbKvp2uMdIUXsrkjKxJhumqw6MzlwYfeJX0zX8qEOV7vTOoqtwIHGRN2WwTMvq0RF1Epmzj5yDeji2wncBr9xQiEeFlCvOyN1-KSRelWJHLFluU2PMu9jSZv3GXtQADpKU46fB3wU3M5XB4JzeNJ3kT46YDHso5rTU9R9GfUC3iKxsu9fG9JLLLysOyQJUBoUrQLlv5g_wk4yiu6V7YRIS04ffXdkiKUDmATM-1cVUel7673-CDkq3RG8jYdKspYgmw7hEfhZCCCyLrQJKJUR6Yck-d0FNQHE01H-CP2LxzowHq-Sol1Adm79NcBCep4hBisrhR_oHxXfd5e50V-GNtHwFuImN6zYty5fjQj4pExi2tPt4vJum9nuMRYaKflYr9BxLpFakM74uh_XnUiR0d2Ryp5OSCo5HkJUxFk08rMBQbl4hJH8xuyUboKWEccb4kYlaIbhMRCiI3LkPCvmAI1tdyNZUDXbpsg9gwNT_q-CGBTcy5jng8MQSIyopJMGqCvXgtktrfYIQQtD40Bl6RSMQmerrXtYcbe4bAEPPKdiAfwnn3mJAMY-g3xBgLytAMaxlBpg4hZBFbDFK7j6nAhHC9VUaXhKfjougXxGjSdqxy0-yfO3X0nsHl8tyM-OvJNNEm3yBR5su-QHqyVnFACrk-ZvebrO-u-EeOWaJO6ayE7Up4H-cNp36Cn9MkFLzgqfdPlvwW4hRZsYKWDTUAwrlmf2cA1fJQ6X0laEa0o8ieZHYCfodgQXva0Y7rUOo7bKbjlJebtdHurpdd1u4d8j3c_kgaOkfCAoMHg5MklXyrHrQ17N8YhRJ2QLL9GJvRHu6QWkoO_n1GmwP_8pI6d4V4Je13SYiZbFxz0uY5UaLsz3BDvHFkd1llFRryYpMvXu3TYayoGYOfinWt6VnDVn5PHPYOddgbTI8ScdVlJ0DSmcwqKmdOO2yNWLShAcm5hRyBCcY4BeVN34AXylaaQ2Wn2K67EFmtRHnEFLOYT6e3ZkgkC0olbVbJfqT0rMoD8O24nKmQJF8m7H-gVggCXtz8UKWHSx4DtCBtfMZIgEksp5kWratwvNRbOgTHrZ7EzpdyUv5ZPhZduWcJ0Xjc41o2dsuCrofVwPKA-jtI7j1Dz-HdvEoJQ1SG8g9ATFrs-vo6oTJ_k88lolEk4stXBUNhYjMZiYeRnYCJkyVs1_GhCsgGDM_JVxOpG0Qb08MfIUAdN6h4450Lk08ikvN2NaLHgNRUkvIgzo1DYlZQqm7m1kDaGO6EqGDjoPXcCFT5-Y6BPdvZWr-SFmdjVJSXXfXE8Fsc-IT0RS9wa8pzUdR0bKtrnFwoO8f26mqgQeSz5SVEMxaW_J0iQ1gOGLc_YWtPO5fRkvCQ==`

* :calling::zork,call_eb1f1b9406894368bf0f7dfd070a2c67
  > * command `"turn on lantern"`

* :scroll::call_eb1f1b9406894368bf0f7dfd070a2c67
  >      Living Room                                                Score: 10  Moves: 15
  >     The brass lantern is now on.
  >
  >     >

* :green_circle::call_eb1f1b9406894368bf0f7dfd070a2c67

* :calling::zork,call_a7b54000dcf148cc91d5a90ca33dca00
  > * command `"down"`

* :scroll::call_a7b54000dcf148cc91d5a90ca33dca00
  >      Cellar                                                     Score: 35  Moves: 16
  >     The trap door crashes shut, and you hear someone barring it.
  >
  >     Cellar
  >     You are in a dark and damp cellar with a narrow passageway leading north, and a
  >     crawlway to the south. On the west is the bottom of a steep metal ramp which is
  >     unclimbable.
  >     Your sword is glowing with a faint blue glow.
  >
  >     >

* :green_circle::call_a7b54000dcf148cc91d5a90ca33dca00

* :thought_balloon::**Exploring north**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf505cd8808191b02956d8a9be8f4d,gAAAAABq31BhXMhynna1Pl2VDjv7-Df1rQF53fLgD0L4FKEg6QJuxEMIyD8ACttPGHuiPgwv8T80NhAlXSRUWPKVZbFDbZIeGvsC4W_5tb3qV8uPR0eI5folM1AxELouulZ5dBc43c2kx3GvDsSlDGqPyhaxXR-aTf6onJocX-5iGxlYrTtj10-gzmq-6QCKU9YZB6qrihSli43_i2A_w3ePTsqhkCV6FIf3A-sGLumj6mewV_CTbvA79SJMx3oQOUl8ABp2cYscupHh_uorvOMb2gnQ9WOvJuU8O9Hyx4wVIhG01--aSAubrkloPi-RiR484pSM7juFyoT7CnjB4diW3amFMCeA0Ag1v9fVl9CD-pAVr0ouW74EIo9LLVBDx7eph0ekjsIHWNv5PSAuXT0wCG7VfdBewARX6A122sjJTXvYx9IPmp7bjKYfsogUA-98GfP4jbBWVR7UFwUMq6Fq6dGQriSMZ5Cd-yGGJGcRz4_g39R2ysSv3rkSh4BO_s2T-bdmtX_8ul1XweRjori9PGqtu6FBPHTDp7QRHEGWZbGMr5a-OBXKadGr1oSnUphedt6UKEJATC32N64jWyhvtG6Pwna1vwD4Asx_M_fYTnciyoFOnCAH2wHbqMz8aD7e55OnMvaKDntOTW1Od9QmwJCkC0dPmEX8JxNOyagHhPEe8N2MhThjMz38WJeOstKaGW8yz00yzxKUKgxNBrvtzS7m9SD1mxtG-il9RLklJ4KVS5GCZNC5BvbJBl8Ya1M3wYBjRcCBIHSuENXD_aykY854RYxVh6etDK3iT_-kcvwbiyGzV9rKTIWSQNHrf4E4Xj-Ss4E-CjqyC7fdIxDoVIN8gB3tDphxVw1_2311kzs-i7T4wtIaI4MedTYofX_3n0ywWORMquUQisWBT73FWPya8Sb3CHYkUrqmSxYTx1ZmDdJbl39I84g7cs2x4EfO9pXqEWRfXLKJwsBne9ap6Edh_9M0g0GONL6jDQhqu9LRaGZczDhhsDk54RMo0Y567Zgk8nGLZjHNCmem-mwe3g_jls_Uns9g3VcGyONgKzZp05Yig4tGA1a1chDzd4rMJLT_JAMgXT8GkQ349lmaw-5qxtM60OeUXHpTsDC2SqjEBzZqym_buY_v6KW1AUJfc3m2tc5KHbl8HoRv1fxWSOIG3DTB3nlCGyhVwxPLNaZ3AlDfYRxAdT_yRwIaYywd_cU8RkaMYW5DuhMBSpWNK10KNokWTRV4zQpG9P1972Qe_Vy5LdL2lmVwWcoaa0Pe4mycmoBN0azyD1fiW0bYVic3Hr_vFfhmTkuuIMaX5ECnc8B7pcqyUiabwLbhRldYhmvZO_Jkx9K2ItUz9jQHbbD8Ys1D4ED1pekp9omWe1gy861mPlu-N4I494gKsyVEKkFhP3envyesKPT7wVnUskRuyzt4mDKff6OITG6ZXJ3CtzPLyEtoNZdo5irzMQqhqCQscUmKlxYezY3m5yZ_0bcwTHpQjSatq_DeYPF1IBsMkFElNHRjgWFmCuzDQrsSNoXz0jqfe9MZ55Qvrx5EVimGEr1V7fsPNt3x-9KKWoTY-yQ6tFoP2QIMmXet8DQ2E_7t7mvzpkNMEuGWAyH2FkR-6xbS_PW0nGvy_p47EL7Qq9H1Ms5JEuTRWXw8mIFn6sUnfmgwLTUTT56nRg4yvJYE4RWsHa23FAoC4_uOGw3uc9FcXeoeOE_8yJZ5-1QaDJNzRHcXDZh2iMGhOzwhnwFW8Wp9s6wNz6GQTwNE-g9uATipPRpmCAi4UifhU_X22eRilFzrDxTjVFWatyV0ZAG6c-JNDI2r7tbe80KaIPHyBfL1wkaQYCsJUlnQPkSavv9Wvq3hrcKBMT2vKJL-qdZJM-9R6KuszXjsFXk0jhRKi8ZW7uAzp7t2RWHXzNU_Tf7ayucStKjiQ8kDI7plqBz5mU9BIwppcYwlJByl71pU15eaWShhgLr8J7arfYzXt1BCGVNMIR-iyw-uICWJhQsb8GVsHAEu_TCaQv2vFp3yC2tPYVN9ESA1fIsTQ0p-qfz5X-FWBqrCZDbEQNVP3ppWpMx-Uv9GanCYB3qCnceeCJza2429UKHSa6uYoXvhAyD0-5ZJnoIj_IiMZo-u0Qp7Zy1ESa1phH2hwMZ0SZrhvhoPJIiciWjV6B_UdHvkkr9HuQmg`

* :calling::zork,call_7295061682cc48698ed2958c0af138ac
  > * command `"north"`

* :scroll::call_7295061682cc48698ed2958c0af138ac
  >      The Troll Room                                             Score: 35  Moves: 17
  >     The Troll Room
  >     This is a small room with passages to the east and south and a forbidding hole
  >     leading west. Bloodstains and deep scratches (perhaps made by an axe) mar the
  >     walls.
  >     A nasty-looking troll, brandishing a bloody axe, blocks all passages out of the
  >     room.
  >     Your sword has begun to glow very brightly.
  >
  >     >

* :green_circle::call_7295061682cc48698ed2958c0af138ac

* :thought_balloon::**Trying south passage**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf5064e5148191aa6cb91191565e47,gAAAAABq31Bnq8N-17OJ7Qf5sLtUxaKej1tv4EFPpy60YkJQsb_Km7rTESfkIV1Me0ceRVJB9qdoM9_wt6cyv44ZAdBhWQqvZlV35DF0f0h3lVVP8dYOot5wxyUgAnIzpXoYfn4MuZpEm50Obdzazvcyjx9ZSWcF8kBTdiM2OTOzdDr1ZKAa9iB_oOAgjipV_6zAe3RRlOgWPf0yWwFZwvplLeqrSmgwrkcEjshOXTi4or9wwb18KofDqVBFDgr1g8Z6hmUAILY8p_a_C7l5ezi0VBFCUtoJHVyRuAbK1bktPQ6hmuoLkAg-VTMMmFg6X3AJHW3wuYfKaZa-vE7seO700oL3_7IndPqYLGcwnGFndSiK1JXevONLD6McZPHRhtfxs-zxzpzraB_Pi4mVF_ReakZRqfcHCHcj7AqSHkFfsSrbd2xP82VTQvETpyP01WMPxLhuM8905dsShLOiEBnZEPUWKOxL2aTgrInyexRjfQJmD8aQlARBDwHuxJhGzomK-Vr8YW4pTDA1gosEGIWCd9AadyZaq3IZEThCzkhQbvVZ1zN-P4YLvjqG7vIHgL7tj4b7NjpohKuZknUWU2RWnqVTgu0Y9nhQXy4Y22IVNaFRnYkg59kQs7wHxcsYdN98QmGH5nyXo9eJUS0vkJApMRn_tknMRYNuIXj7sp1g3sCueOcwxRWQcIXGOlX49l7jxk8UBZ4COXuQQTgrjAvtPn45_v0aa9ocYY62JEp4QsAUNokQ3qVZZnnjrHbiT2fj4Sv3ZWTzWgCYbsjRpFAFOsQ5gLMkNAjrQyzoHpqxHmMe1wk5_F_YoNcOqWPIqEfrfc_ovheib0rwsLsX-yFdTCC3KpkG5BkLVseuCLOKxuBfw6h6kKCopkV93kjxu7AJgcjPS6BJP_g7t3LqHGj8Bs2bmaMqec6ZMijz6Lj9U8at6dFTIYEiiI5USPn_K6h-f-fGOKzyiGspCiMlg9eRI9vSbgSDETVK0_gzpNb4WX2DxWOZvrV-VwK-6FtJ125G5u9QDWJeBb_YknFBlb9iwIuTMwdL3cx1p4u4Xv-woiszwbc0pUvozhG2G1sWLRdtUBwQy8K2ntpgmbiYgHWDc_9xB4NIWcMpFa3IYfPCGisisS1sJQTI9mjYGoG7ntuoUk0_PQFRHo3dMEMX-_-hdU7SoQGNr53DAYAGxAiDEQJE0JdNOwE6K8yjICMry3M-Di9VAyiFHrJtKf3PecntCQc5aXXCBtT2k5N4JZR8kjOKfb1mj-knTmTuON2cKmq5HmgcRjdtLQUtOVaSBUXIsFfCSab4DwMrvGIH5LenXyBLVMiTbF8qFDc_UEGaweP3bMf5cbb_U1UGo98pc7NWtZF4BuvyFBKTg4v_ATlvG6uclZoSHWCPaDAcdTK07tSp3n1Deq-oVUVPBgHG8-t_FOIn6Vi5k0KEq8AZ2GeyxFu4DZMkzXRr7beg-ebHojou8TJ329EW6GkhTZS0M3Xy__CdXtY8kIBQJtGkvInCtHPJwXq1T7LH8QpO1ayyhFeeKz8lj1_StWR6i8KulLOCqmVvkiCpNnmgsowqHMj2dx0UK1W8QTlDSm81EbDHBbA9hjrGS0VFSgFOlWikj6UFny2VFaZDYhK7LR51wIFohlNELiDS1VTtljJnIF1uu6fe3aeKzi1O128eNWYhnfYXAqnF8pXKDqMRJeHPPuVdkLgGkUNHuSIa1mjppjFudlmEcgkCH3x6SX28_w8pk7pcvIarWIDsNNBROpdrwwmCahCBabNmyrNG0D_iQhQHAsCGFOWP5keyvaPARkBQwcoHhB9RfNXCv70Gv46kAxvAM2vr-yISvLvixA81Nb08r8KjkuQFxZqMK3DpwPrOijtajhBba9Z3tN3fQR9cOvxjdf8L_hCT0rpChj93Js2CrKwNL7CZuOHpQgqUZjIdRSfM2x2S8EsEAgmOBi94u_uqDhCbYoBg15B2sGXtq4I_CFI7R1GfjXS0xVUvgN8EDOLjYo6RZn62O-IOOE-CEVThZOAWolizkbMqwofPE6pwCs8ltlZlUGGX`

* :calling::zork,call_1fd67ae756dc4c2ab388de02c4c4a9f0
  > * command `"south"`

* :scroll::call_1fd67ae756dc4c2ab388de02c4c4a9f0
  >      Cellar                                                     Score: 35  Moves: 18
  >     Cellar
  >     Your sword is glowing with a faint blue glow.
  >
  >     >

* :green_circle::call_1fd67ae756dc4c2ab388de02c4c4a9f0

* :thought_balloon::**Exploring the south crawlway**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf506a24d081919dbdbcc7ae1565b8,gAAAAABq31BsBESqdUM5TyEn1QmuWboyOL0VyGJ0HopSAmUWX1jJ5_H4sql5zc0kXwiBdx8-Rt7OcgZf149TgRjjh1vCgYzskPWsB-Z6rjomJqiyjDE2KV0Zet5CFbG3w8cR2B5XLWO2C3GVUGolgtGYPU3MhhtaIiFZXS-1ry47Jcnlj0XnIwyVNS4qr34t13QiOai59ZrQKsLTsm3jWBp3JdjK4NfQStqvJmqhbC8TRkMDbBeXo837-tXYU9RrR2iSu8yN-JFhfkXZO0Rm7hwpO6klKEkDRkN-tWASuaj0dLZ9BgE3styW28OVmtEvenprRbJmIkmAGXNdmTCr8-TY8g-emsJBAwbZhaikQL_Ec0EsTYKluBOQoE8qtfubkU1SbNFpvfPEEF_T97KzYik8Dc0NKRI4VBBo95YPVyEdvTJcTP7i4qHc1EhXkH7RLhWzq3qcHxwqzlro2FBsv4_vRia9bFPl5REUy9D1klHRTPHk3McvoYY0ABax2Va_WULTR4Wv_PbqAJlWvxL3uCKpc6KGl2ixr498h_wsBhASBsOCgpUVgR_ljy0hNKoIeDQqPJ1NqKCugbcl55Nu5rhrQ6kiXakIxALty0Ejr82yd3U8uwUy9dKrG5Klq3BLRZyGEHpIZzTyFo323AhyUU9IwoCXty3fwlN6kQFxLpBn8N9ON04VJX0rTAmZ9mWXgyGRMEQTaT9qKw75rqK76bqw5CbEz25U3jzjgcW6poerdiINbfktIQ5OKRo3jt2-K0pVF5Mj6v9CYv8UjKTcVzgtdW3RND0CkwBill_H1YEnsCtZn81c633cJSne71lDN9BfDzAr1ySMgJhb-FXJmgBNZ2pO1KMNUFfGD3IpVNUxgP8oGPnFQjrw4OMEehy74GlxHN1enO7AHIZ5spx-X6GlatvDGJbWySZW1VQmXOoOkVg6yxOAiPJPCs32ym_zIelrdPKsql-kTbBqaIkarAwmaX1Hc2BYuIPkVLt5j-3Q5D3JFZtn_RsSuyb-ntJBvRLKRJdemi52A1RQtIWKJ5zgNhjKv3zRwczTq4MDxUnfITJ1E_hEEBESMbmHEXGPvVkft08qfvxwjN2CdKRvC5cyMc059andUnk2lgii2ez5iUxGJz28d8dUIPo-P6kgMEo7WCg_aFzmU7V0AM7lv1F4t1fx9Hmu32D4GhgCghBi1dgGModKongzsgnWLSHOzqLKWxnWD0ppsd5FoJHkcF3Feyp8DhWnsVRzX4_IZyvKbPTDF9zO0R3B1LqfriEv_7KxBshaje-EuxMDSXXXAE0Gkmhcnz2Y6B7GnwrlbhI0IMjSg9nB1go7_GWLrBfICoGUtOrAtzuLlC9KbXpvempP5bm9Werh9F4EJaW0-3VmZ040pDNcPJRJhUTzEu1untcMKz1wxz5isJJEjFkB1Rph3opIcs-1zEzeLTJZCWsA4Hss2uFUJBn090ORm2uZfyX_ZvP1-8M1q56fZcYD4P52JPghFMHWI5OLXC0QN4fpe0-etk3S7HYaYyZK2XyKV6erl8lJyctlAIWrVZru5F6h5krHu_aSoQrnjtqn-l-1l_7G8ek6gxWgf72gtKKNp0YtshrW_QOSp134nH9FAdTmn4imhMwZw08gz80-4groBnhCXKFTKicyqqNBZO2y5FCpHKzv3z2A7TQfPaM_S6uK1q0B4Z72BcnUsQDDNScMztMTHFGtdELlXRt6VcV1iuNNN8UzybHxqnINIy7S1Unlt7qYALrjaCee1FZYaKVfSKzM1jjJN1TPR7sd1m7dHVyz5xjMbXPQUlZjh-c1BKBm3KeQ_0Vo-xJhqMeT88NVgEavC38sUKAVrLATL3NmKlm7X7AhfX-Qla5DZdm58V4OjhtelbFePcAUgWes9BVcPf8a9pB55Lo4QNbxEOcERkK_hkfSFdCUSuh-9vVusDQIgMdZHut654RkgPHUUhaX_cJhc9N8zSWx_F9w68hWSKpkXNy5Ymd5_L7dNgpoFybbI08dZ9uNllndyTL_r8U6kJjcsjQn8dA6Uhn-OLtF0H3dEYR3uLD4`

* :calling::zork,call_f5c3be8cdc684580894cdaf6a6308ddb
  > * command `"south"`

* :scroll::call_f5c3be8cdc684580894cdaf6a6308ddb
  >      East of Chasm                                              Score: 35  Moves: 19
  >     East of Chasm
  >     You are on the east edge of a chasm, the bottom of which cannot be seen. A
  >     narrow passage goes north, and the path you are on continues to the east.
  >     Your sword is no longer glowing.
  >
  >     >

* :green_circle::call_f5c3be8cdc684580894cdaf6a6308ddb

* :thought_balloon::**Might get basics**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf506e5c248191bc9613ec2333a91f,gAAAAABq31BvIMKOh9e7j6sCnzMka7hJdpQN8oassvrZb8GtxaO8UOZY0O71uRT1bOtaR6d9QZL7KymXutakMQyU2_WeE_yx5YXpKERJt9xeUSyx1B-vnblmczCURV_68wCxPylsPkwhl_h1vKgrA9xWI1c3266kSS5KL_4Km5xHwCWhWdFx79rQQ-nXn0QHH-a7yq0fInPitypDxUTmATeELJAn30JSLTpaSWreqG4T_41tE7XKPoHRmKyhxBf7YS200CvCreuBqLkxP9UkIwIxxlkT6ffjC4l9nfoWTGgwYriee_y1_rjN0-fdm0NNH3BGSxNdmb7dgdfIflrS92gHIJNIEqwuFMBzirutzuuTWe5Oy1OTfSZN8_1KHunxwUqr6j7p9oDLYsKcDXr5Q-k1iSCvB5u4wbz962SvoKhHmjdd5XUzfuafRM2JOZmTTzQevYNWFCMpl5R8i7cMTVtpUty7Ye_7KM5rsoLOAFPNYOQkpaAA9PrIcpUUz6y6WxVkbrsNIk402r_r4jTwccWgfhCtkvq8cNpcV8W4jDqCSaE1aZA1k833tKOiA_FZrK8CuFiwJzMl1kw8ZQyx3kyGD2Z6URVCgbUN1Ww6gD4UcvlV2GGkMPDqe8B9MZOR83or27eFG_xQnFN42mZypnKBvtEPCJu1jnKZciazCSsSWzQuto6hN55yvMjEsEcemseCuDq7EI5fZXpnJ2WT-k9tlfQTZ9EXC3huXVyRMQpQahAsasI9Ose5RFm59BhkQsiGSt0_FATGuKGWq1aZ-HZN6G-sYfeLjAA5LaKvFFWqr9Ui991gKIOYrx3UuN392DA2-No0IqPeCRm0-AV7V5yO4ZH_u30-6GX4He-HNQQAFfm2yGL0PWgYoOqvb_AANP_BYHOI_gmMK0MqKZu_7PjJFOgnHMtqyL-vZq5g2Nexc92vXx5gawu_glxtb7kp5GtUIH61qkZHRDALl_Tz0gq4V8l_fJ8QXLqnpkSFKS69SQWVpL82n5XEODZMijvfVL-QYrriTRNmjAga6GaBK3JIUtmfDT9i3uh7TICEs4AED5DwKsle2olmqEi5H-R3qFStHEPGXAr_1wnS51__0IJmgmvyqt6I1yjqpc2F6iO-8A1CFRxUNeZTuZL3DpONeWEx8y3A3xo33bmo2rCVba9RmAIJwg2n5gbWjseqx-bixtwzHsulvwO-HFU7i-HlhPBpKMWsfmOZDHKNINJYQeshZUE6ZDv5QF_RcaTdCy2qQIpo0_miZ-hd3v5O-RknmNIdfiVE-yGBP_Kqf3wWQrT0Dl9IwivgeTRSULAhIPrhPJ2ZYE4U6t1ivrpZSnBvS8dh70vJiA9C0XNSK-7JQKz_MLCUWQgNRVIDAtYkO3m7ODI3peo6q90cdNRr08zY8ikmy8vR3pdhXUSIk7CGxz7T6aUbYg67Yr_5QOjcbWM7mF-Jb8nQS4gGYY_CKQaf9N8420CDQd96_B1ZD4PVeNtLXJBZ1cLCFAPvH2p3ZVVtjTVMM87IOwcgfCQwp4-J0H5NX6ofnIXHR8dexFZNb2XvtJOtVBZ6SeOzC8LoPH0LRSENYHYyY2ngh24mZMIE4oyq3myjsbSavh8PIlNTLwukXqjqIHA-Ng==`

* :calling::zork,call_f65c5e8d7d354c3184392d45266d5957
  > * command `"east"`

* :scroll::call_f65c5e8d7d354c3184392d45266d5957
  >      Gallery                                                    Score: 35  Moves: 20
  >     Gallery
  >     This is an art gallery. Most of the paintings have been stolen by vandals with
  >     exceptional taste. The vandals left through either the north or west exits.
  >     Fortunately, there is still one chance for you to be a vandal, for on the far
  >     wall is a painting of unparalleled beauty.
  >
  >     >

* :green_circle::call_f65c5e8d7d354c3184392d45266d5957

* :thought_balloon::**Taking the painting**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf50724a408191a25b8c050398b84f,gAAAAABq31Bz-c-8RTYRKatb16II0rx-4G1O7TnjdJ6E_llIO1r1GqGR0RcgMeDz4J6JFKYcPM7xdSVjs_NM3kDi6mQ7RzQpG1S7JpXYO7_71CULMC2ND6BSX36iT7y-hqpiYrBP5sNHpxX1FI-nCFP6oGjWCjZHhPkJmvqzstzrJu7m6Nq24V_sjaVbo5bnZ3xj9SPO5_FGOiNAfiWova6rnMQsYsVa_voyp820HEWKqzyx-gqWpVyRwQu-zgpmM8OUxo9eWbaf4CBKh1dk4XDSHtLr3ksjDFWoZFDuN1yIE9IE22aQszGwGKMUsp6LbIQn2tv94g4-JAdiK4xP64CjnVj1ZubWrtAzf9a8I3Un5XnSNGi8y1gaUnKAqCrh2RPb_N9AMQ5Vbl3K4l6-LHIQoQSSELth3LCUsA4jpBqtVE5Eih0bTXDrWEE9zyA8Bqp5_X8VZMwrFMTPNW6YjLIWd--O3_7PXgMhzC7EsPgLVoIQLgvO0vAljAzEGjivTNiAYJXImCqU4rNNtUDmyFess8Dl__WT9Mz5wAbi4NYocBQvYb6S70KZVXQjlHT23Gk2ctw1OVPwWIqeL0a8zO4tU5H4uonDSItP1BSgyBjjglK9EtVhO1rPs2D2lbUn_xwz5iG2ef1ol4AjdoZIAf7Q8Lc_47s_SSAps28LTYOdiwgex2IVCJ3UGij_2nc8sA1Qa_HRLRNZBYc3CDpV3uG4Cc4frHDP02_UKYUT77y-ser7U88qUQAGuChcNex82SvAVUyPuO_oBdnBPW8E569Hx_FO-KUwS7ZbRh-HUmRh8tQeQWevEdjijFpaVikGvbNKoufGIH2P9BG5MGIZOCu_nVc-Zu2mcPuvW144an2wAlU58GVm02N51ef0q7uRCJCWrZRyBGwdLf12oSb4y1H3z-VexZQEsuTnSScA7brxhBdbVC1MiVC5ZCEiAwxWbE4N3hGYmqqgPYS237CNvf4tAb4XUPbINtnij3KKfJYQeciQHj--lnxLpip6KF0WN6D_9NPfO5eR1Bo0pAfY2jP6PW7Dnh7pp2zw1OUCWUtVW9dFeW5fjZAFR_pJXZYtEXZvFb6jpPuEbihQqrcma8ondBB8ZTuwbXslzDKO2ahOtDezNTDZrq9ZWROAXyyw19DsjR1KRBqjYl2aSNXuGMESBmLiM90RkXWw5PsThPvpI5EhDKyMAIOH6DRPSDnz7FpkPpsA8qTpdvFGEXkkWLHkU4O2Fvw9eGfJnZBLhALj9TDMnvt9RWIrI-77UwnSTYygAGvEAiPAPYVVPr09WxfYtdpnIFQclEEMWtX8_ehfFjDc1evMLDbaidIsGMtzGNKQ9UKsuQIfrig6pWyciDsQ_DX4qfEux3hhxaF2NuN6QDw6552vFXaWJvdHebg42nLe0sLXUufZvthIKgHgmM7pk7jtIpvsXEdcQj49I_AH2z-pie23fl7NizLoL8LSDIWmkbSlSfc8YNg5hqkhEBGNpVgaHMfVvFqhWVcj5F_fHt0I7tgeMdC-HtJhr0Fqoh1N_QDOIzL9TdDEZ5DgxTT3XaNLTzGYhQJdi1SlZWq8Fhrq45Gz-GvjVfoBrl-FSzHR1jJTLvCuihfss7Gc_M9OBuQIat3w0KnpG0TkBAv1jEvmYjcR66bkHh0r6uWNiOXk4eMf6Q4l5iwVwhLCFgOcTJ68uczQNV8025SbNxl5O6_JTylQ4iGzEMySriqbVrh_s6t5txDz2iGS0se3SPsGegZOEvXaOxFP0gGWOC6Bini3oC8i4s4sujT5yA0bxjvo78E91PYHaiZh4A0w8W1DMXu984Fk2TzsbhMgVyrwpZodX1uac-hZ2qp5W12cMvu2z2EHBmdaEORpOouqcdt6ggQJ7K8OTUvuRFvOhuMchRhBDgw1es8=`

* :calling::zork,call_bd48bead721446b1a9367a6474fdf2c0
  > * command `"take painting"`

* :scroll::call_bd48bead721446b1a9367a6474fdf2c0
  >      Gallery                                                    Score: 39  Moves: 21
  >     Taken.
  >
  >     >

* :green_circle::call_bd48bead721446b1a9367a6474fdf2c0

* :thought_balloon::**Heading north**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf50777d6c8191b5012c2acb929ebf,gAAAAABq31B4tsvThq9TXyZJjxeEp9YunFZpy3z7ME6v6pFsvkspdrHE8j0C0R97j441g1tRw7G2NwdapMrBvMxnkcP2ZEmtPIp641q1PRmJPdtWt153_EdSQMhEThyJg5DN-uv0gSIwNFXZvxXS5ZbjTLgeEGkwIisWv2y5NgKRyqpd6je0FSD5NNTzUpD9bCQy1YBZzQU1Sdezt80l58XngjDuW1umc3VEnBhihDwTS24WS5ZAYeICXAeF4JxnonZeXxS5I9JXTS3m2dSVPNXZhMiilk03W25tajmj_oeIka7Zc_DMs2q3ZM5YBjhSHR12b6ge806QkSIbfDy-5F6hrInvXy7ZKqqm-xZVSKb3Iz9T3CErVqtjxeQ5YVxbEmYDGAiU6-z6TmFyyD9hxxFqms1m7nRSwFnXvgAVC_hpeh_L-ZFVXX7dVIf6pz3BNi-ImzFJZwUWjJINCfEHDP7MUg67c87mciYhVSTrfg8f21u3_B5j4n3viUEgYR-1Vo7-FBsMKgd2uAxYPGw40Y8p_4nrrvhLejtVkl10mB0OzFdgZz_Ep4k-1wVFPA37jyp4FlhD_LONGCc7o6gBTd5LFuYcNNZn97I52WtoXkp19hsc3v6NF9YWvk5kSNenONKSl5KGLgtpRnUroV0Rp8mIOPvVaJABrgIs5qhMoOlRetWrSnDsmMR5kJ4N_gdo5_vbcmifL5E4amHRyRvWc9sbaV74o5vgFIFahFAnxOlodpa-21HSpERJosyIkJzuTTN6yOvdSxEBSlLaHhtWW2hZPu3Trt2Pcd7NOWx0QR0gBaRlYFmOCIbpbADv-VMsvDnS9EMGNp5U9kBx5-6rvWp7uJYYag8ffH4JkVGsCUh-KmKvd3iwiPsvXXO0Gts3dtNUU94KgZ79C9Sv9829iBofY978VJm5F_IVnv0MGVmeeiQ0lFV7qH0QsLZi5lq6k4U5Ckb_lO8dJlXvrFNU94wCEGODP7IH48DAttX_rZjGgUJd5DJzLI8FzxjTN42_fkSq6sH84SVJbQGVk1dX7am9g8tvh8m-ohPECAGARp2sH3g7L3PNe6zQUu8hvY316MWYGy001piXmqZkmL_j03-sFa_oby4yGM7VYXXylXCyoAZ_PEuZq2i1w7xmTzyCcqX6Y4b6gVtz6IhuCrDXqr_BZm0A9-tqKmVzuqBxGzrjgaPLO7OpQLfyAyGTdvDMnDAkHRj-YjvONwZfB5qHNjx234nDOE_5evA0U7iRcSLlYkO6QcTkHIGq2jHpH1NmO2fy9-4qdf5RISsrEjOyKtdVwSwcPRIlxc8vvQ4ZN_6Ta5nu0dsXdk7h0k1X9v4ho065PuW7ZyOBKdNC4GzP1kA03rNwlqi1t4-BV4XH5rRz-IM7cstnr-bYub7R8KXzZgrenr_GSAKucjQ5opJfyiqSZa_Rkx3qXQemnF9gvtNA-pYLjg1ro6hIS0M75ljSiUF3oyB1-dpUYXpIAhSPCdGORuQrr-ywAl6wn7oe2aCaCRJZpZRTZQh8JPtjyK3SmDAGKfNIlAqpdykypM2Pa_CeAfSaWK8L5XwjV8BXCW_QBTRxW7bp4xI=`

* :calling::zork,call_be6de81d9b0d48cbb26d0f116671e671
  > * command `"north"`

* :scroll::call_be6de81d9b0d48cbb26d0f116671e671
  >      Studio                                                     Score: 39  Moves: 22
  >     Studio
  >     This appears to have been an artist's studio. The walls and floors are
  >     splattered with paints of 69 different colors. Strangely enough, nothing of
  >     value is hanging here. At the south end of the room is an open door (also
  >     covered with paint). A dark and narrow chimney leads up from a fireplace;
  >     although you might be able to get up it, it seems unlikely you could get back
  >     down.
  >     Loosely attached to a wall is a small piece of paper.
  >
  >     >

* :green_circle::call_be6de81d9b0d48cbb26d0f116671e671

* :thought_balloon::**Finding the paper map**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf507ae5a081918e9cbb7166109498,gAAAAABq31B8FePraN5SSgn3QpnG1ounEvPdd4GSMmrBiZU6HnoNdflCX3gG3pzw7--fu6DNYbZhftwg91Jc2W61OnscVgw6mlr_Pf02Pe3MMP_oEDqbKusdN9wiGGRBRhv3ugOh9b443Ozply4m0Fh7MqV0isRW_aW8dzij7qbqcj-v1zjzWgAXIpkMJDRSKagS3aZS6mk6VWslgAq_Lv0swaJKSxZF_Vdj6SxYhMDZnCpbkQgQzGOS-O2CuRuTahcIzJ-f5fSR7B3HLSu6biJIx9lIZ5KySqsbdX3vmILYPflhjVvf1e9rGD2UoAlw_sJaC3VFLJcmqdqgm7K_DiIRe8lK_FqTMOrHAKxXM42dJKvovZAPezDphOh-SiEzb9JRaC01XbuyYFkGaTDJsj_IATUZxUX35daL4ytDE3GBp3jLj28sorO2yVMgsru-OS7st2LgYcaxfrjf9gJOcuG-ixvAe2Pfjmr53lsrE5jkS2zIYlxSFPHJEF7XEwoQm19CSh8PzYJWr6owDt8CUUxKdfcG82-CYzsKVLL8TOTQuAKMF2piV4I9JqZY0mSEPqm8QXLf_3NGO-h2beMIKAWq7X7HMPoWvgTIIvUHvZCWHj9hQI6T9DILdMzWVAh71l99uVJIYMeukqVMq9CJZUhhMIbBmIOmWR7LC97DpzmmRgrt54sSABEZj0Z8tdtVgkHkOD4uMgd8QtBJiDapAeijnqcOwUqJ0xwMGZ4K45KrM9RKSlStxDpN0KPyQFpteMk-2qj_4CUVGWK6lc-wLpw6Xo2Bte2yqxtyFOxyl60I56j0tbN8ljstBVxCAw3XzKSCbo45EsA3Hr4glfL6qOfzabp6zlGIb838T43myb4Wsb-wddktCeOnVW1bq3TywANdTt0ybZKUNthTkZvORSewe8pdktmxXq5OxA-IrK6PJfDORXohCYpfpsacHjeLgF9mQHAj7ZuBA6ZxuRcnsGrYUq41HfKJSJVNEiH-k-IJw0GhwIM0Ij7ojxiv5yy60YvSaI_2uhJbzLJuXdXgd3nJzYYkmW9xS2_TmPUewsFRafh6PEd25M63fA3KSs9V_dz_24yhmJsMC3B385GiIRvPrCNn8Go465Qw8J2KobXz6w7MYN-6FYSZ1VGuLMPDzgLj8dYpBWc-vLVEIi2lBk0L2L5OlZxCUDRT5hgCHNWvHiVgNphhbBsI3M6PjsBZfsXYAAaiplwvEEW9bRVodYCMbQyZYpSaneUdOwkce-3cWiDz2zlC5tbMoyGU22A_0KsP7I424ClSNMZlhXt1pbmT3Sy36dMzQSrKcUyGJagCiX5q13nOVS6FQou43IAN0CwNPdYx7xi78EDCXkUVpJrL6_f7c1D7H9s8VcF6msIEqQSTadTcWmJuFgRRptgKpOpFq65TCd3brKscZgsibrZqJhS_wm9EdAfbrBpMaeqQaPpusXI5zcS5b38iZ8kDUDBwgNi46L15v-MjKWJPfD0IgDxjurZyY5VFfJLUI5rXEdGWUqh_Res0cFpyiEK2VVLMsEg2cIL_DT3liDCVk3tfRSp7dPMt-DfPpPIeGTQsmPl1zdulixNRv6WxO39B6VQviAvZAPi0`

* :calling::zork,call_3aec250d2a6c4766ab526b13b48a9c3c
  > * command `"take paper"`

* :scroll::call_3aec250d2a6c4766ab526b13b48a9c3c
  >      Studio                                                     Score: 39  Moves: 23
  >     Taken.
  >
  >     >

* :green_circle::call_3aec250d2a6c4766ab526b13b48a9c3c

* :thought_balloon::**Checking the paper**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf507f36588191a3da5164d723f62e,gAAAAABq31CCqLTU6PBWrf5UBQR_vTHYxnX7g2D2F6fLVC2fN_L-5ZafzWOtc6ZSdf_GOoXrYS50e4fhLAgFrcD_IUcZybkGHzXr0rBRDPM4fiti1RAOVZsycYXNtKmhBUZ7VELYP2_-DFRfUDSStEMAwN6yECTRR23kE1DxhClqKe3ZsSDNZESwkdSVDQN1WDizy3c9VNhCoumo9l6WGkSp1aTIljW6lgajObJ0WS_5qiHPlxPvdzAv55MRl21mKYeWJDO8GFaq8hIM3olPfoBeQdKvKIp4gXjgdB-N9_SkiQ3-d4pY0wVuNT-UrwNcsGXz0HgswohXoxAxDeJasA1K89GNM5gkBCLGmD-sly5wB4piYOGtPhyfQe-blSyZ0gskFVzXhCWz-cOlH_wgScpVIrIaIgWDi8uHtQgTmnEo60tNfbGu17wdjC0VYgnDe5suyWnCNpjjRpWncZfneTCbL_U-fkcAOEb_27jRHvqX_q14DtsdX1lXK4VoTHl3WBv-S9J26aPwTmMWLWaTXoFgeC88HyWIZrB_ZiZX3wQ5jy4ReA5HWiVJ1yqu3dY85DN4gCAcYz-8vMX_nCtRWUXZr948jYSFol_jJGbrPzPMIma2Z_lkBwoV4tWBnRGp4PirDTjrxQOIhX7vAFYRcZiSow1VmU-rkegzV9DGpbd4VsKvMumyjrN7v-V7fBNKuCDsZTwLEu04lFhyKwX74CI6fK-TAMv32Gqqk0TamsSpWy4HGuq4dDX1_tSXZ81Cg1H5sQSzx6XgekWHx9MxfFCvBdQzFILGzrDcIYNTqaTqUElbleL5tZTbt6kxwrMW_p9Qgiv93Pop0uIWvNPbdJCe1-ijD-fNIzMIAXgwuPwLuGXOJX2fJcbvE7-0mIoh2kMa5XVRMob9oi7NNU7eOaWn0HHbyRStXO6oW6XGhm8t2INAvwHQOJvPqBgjgtf72oQwrXQkqcpBTGCotYukRmPiKvCUb1Sfs8u8K_e4tQ0_UhC0wWOZzyOu8yZTwXvJrJSip6J7Ei5Chkg9uWi8I55JPNvOLD1zgUEyQl6V03N5OncendgqDKsiwIcfLRG5SdStBsc1KzIrxC94zS2KsZ5vmXiRWB6JR-q0C8zkIKD7Zhv0zlMeqfhsWIRZJP7diQ9Nj3kDSjgmmPYMLiuJcCHvrHk6KIemdqiWXCorhVh4j6gpvlbwQySotmZHNPqMOQZRGZJGjOQATdfgdJQRghuj3rgzwXqg02X7L7qXxTiJHaf5c51X5J1lWsAqErv4s9QlA-L-bEWVc068yi7Vp_rjUoqsvViAbtgOvkiH16WfKmy2P6llJtYOGnlGUyh7uHDpyL84tMPa7OnL8tmG6H2CE-8W36zpKbBblEwusm3TaDGtmPVIE81VI2frrzVkcSPh_He5CE_Ar-04tZXQlrUMIKqHOU_hBFsn2UUwfO5-lZt9r9bffCka9QflRd4m000QmOqv_vejErwnBBmARFKRh02y2gm8jGVsB47fravVAg3QW3yxLTpzlq42TltJvFQ2LqRGs9ZNHDpr1Ft_cjm2vvxM5und4y_rtyJEXU2k0gF62ki3XcZlvVyeNTNeYZ1E5A4HOBaJZk80-XojGaDqYsjwjVQ0Q7xXLAqWTf9toA3vOreojuwF44X5-z4_hBPKldQWc2HkNSfctUIecwHMOgroUCdwuVE2r5YaLhYWxge-Vaa_UxHNbznlX-c5BL_9bjgvEz89cGKL3O0KCnr5fWXfJAPdq7RxYah9JuzkuDaFNM-2x6hraVLxNHXncxs0FiLfF-Bnyagpmf93w4jBoZCW2UnxnGLcfb_WRq9f2-ThLnKPSXVuihnKo5uvusUJwVktepMrqfWlfhRDlMCQ8ux8C2U9QbBdEcBgWuoJOPqxv_Nt0bA8c1_yHrjs35z9KwNTJ1tWq1xIGN6WtZPCGsCzJgMOvfzTkIRXPqDh7k3qIk1_CEm_9Q9E1bG4JclFcWEthy8maGJiOQMwBpnwuTeCSRVoDg==`

* :calling::zork,call_77372d08a83947f89e07a26f45006d3b
  > * command `"read paper"`

* :scroll::call_77372d08a83947f89e07a26f45006d3b
  >      Studio                                                     Score: 39  Moves: 24
  >     Congratulations!
  >
  >     You are the privileged owner of ZORK I: The Great Underground Empire, a
  >     self-contained and self-maintaining universe. If used and maintained in
  >     accordance with normal operating practices for small universes, ZORK will
  >     provide many months of trouble-free operation.
  >
  >     >

* :green_circle::call_77372d08a83947f89e07a26f45006d3b

* :thought_balloon::**Checking barred cellar trapdoor**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf508575508191aea9795433f4d1e8,gAAAAABq31CJ1ksX7JmLkosuUtcJdWFs68PBTbDOtp7ZUtXTQC2UUKtlr148AerLMVdRijq2B7CpBTFnBQU4Dcv24MAFwFWD0rThJNvbVgh9cXlDKymc16JCB7cBgEqL_xIBIpCXAJcgd3oThCUzvzAjev6Dt0sMWzC2NuAsEV3UhDwvFHgjqiP4CM_WhV0FWYap6pacOqo0MX5d-i_gmWk7sbXXQrNl9vB1HuLXX1bSx1mSqKEduAc9hb-0ALeIrrmzhVbi6zp8WmcDkK8qle5HVrmZj9iXAyULGOwW6U9t6T9U4d87BaRKbG69F-C8imt9B9yBGsT83IJKxVWcmf3DT3BUca8NePJm7uK1xO9XyB8eLvcUMryjq4hfZsmc_YvnTHiGk-QG-TGAESWet1dL7BMZ2y2EZs17I2gs9R6CPf2lfYk2wBbV3c6mG75cf2SlOOEvv7bpYenkGw3rSpUuKoDwt0AETHey1_NidzELbT9WjEbxTWY9Cu7tJRc6zFAYmn7NY26MfGViQ4joaiMs7aVlRvltZWYIYYjx7cNO7xch1k7AIJyR1KcgpO8F9pq5bSe5VAlEWmhr082iiVUYgncQLSdSmkFxiInO3qyguA9QLu3xztLCludnPrXjXF2s2CxSvD6CCmzPuy2dzTdP2LgZxQZMdWRKYyCP-PCWbWyvSxMsTkVKU_9m-uHHaGLy1bkTVvw_WryMQhRLcWyulsOh6Vv8oeZ4vR5FMYgjygWP_iUF9TM51L3cxbqYosr4mQjdrOn0-n202hTjXXa3Al5ts6GGeFRHrBzZVYYv7oTTOvcsP49_bOxZhlxtas119rHPM_uhPn42wSkZaZGRDG_3AQWGDgsfIJhIVqz1XgsO92wS3gGwokfmEJjy0ZuAi3Nyd2NLpXKAiIjvkSoxBUtIjfVDK-tasbzmDDQMrt6LrJK5aXlOKK1QpacpzaykxHWtN9shVN4D5wXd_WvVxiR0Vb-wwEO-wmuDpOwV5fb_whjYIqGQWTfTP7crJ_-XdlvV_45cEKfiIyAaiGvZngKAZ1v_7lKYMWar49gl-Txe8hySJ5JbyDePjrCkbIp5kPC66sVSMLGMqWN_Jh3c-XGNOyp0SyN7WO_5XkbijZ_1lwNODqk0UrzJmosTSHe77JB5unjwwD5rCTBu79GBj0myCSg49olS2z6KpIlyNQ9662GdFM4W15QhNg3FFp16diAz-XN2mN90-6v1DVmEWmIAaTm82BvTTnt80XBs8JJTD5aoOmEyo5RftJ_Z635Nrl4iRbMU68_XjfBxFIPcMaMyB0yAWH-STf1HhG7VAaf0JHDhNhIjEmFeNvp-wZGLuvyNcpV1mFi4fFFn1ZPGHyA-dIj4lnl0ZvFuvE4QACkBKrLTho3ncDBbDUNmx_XaKDUi0jkK2zzpTrlq-NavkhEtq10bYVxAw2Qke81tyFWdDFJ5mUwbud8LajnegYZ1J1FOwDLdL7loWkmoR24Px8i1gwNuU8RYHSJnmo1UWCbuzAz8u-4vcwTCBDvr61qIeXPq0A65TWMDzYbxWPVLwrUCtt7dC8PtgleOoU8PRI7kRgHvMoTT2V4kqmfOLrTkiyVoYt6j3wyOpqyX4AEnRDY6TJl5WLVCW2xmXYiFtQq2q6iCqFQEXpTFUdtT7pzhWSm_HSQOPdWNoBM6jIc1Y7vWoQBrudEW-YJb9ZPMRmjudTmBJpDr-gBEAunJ5mpPUvAWPPddpviKQD5fVizi4shETssT_9D9yiVNl8abih13uwKn-WULJOwB8Za0fBrTUtCOwxmmyPpfIgV_SvKjRZrveGVMWikIhJWvyKf6xm3O-PWVOI6fjRqFFCr12Kk9dr7AQM1sMBsayS97_6tSAuub1gpNEhMQuliVJkte2qMS4y--vPXEbqvFVtR05gmqBmVbcG2wxQE578Q2UZ0pcBd7t0iH5v2hy7TmZXyFPrk4JvzJG1IgdI0tfKP2aL7owN0sJiAQh1KFy1RMpYsJSAUg84CF7k-PTOpdyTVaH5dA4i0Az7SvBVgXnsl1LPwa16T10FI5pNjKnV1L8-6ANGrxxZzMJNb8Hn0s7QdrBhvo5_FpeqbuP6gfe43vZ0k_9WAMCx7mRbv2FlhFw1beGsoLu7tRkUycJq3chu6Q6Y6L3ueVg3l4vvRL_smiNLUHCze_UyKq-Tfu844-mXx88Uadht2amPOzkkdMg4KzyCoYSpSQ1hcI9suyzO1K1jCXTZoaJAfM`

* :robot::
  > We’ve found a solid starter kit: a water-filled bottle, the peppery sack, a glowing sword, and a working lantern. I also picked up the leaflet and a painting (treasure), plus a rather unhelpful “Congratulations!” note in the studio.
  >
  > We’re currently in the Studio, underground. The trapdoor behind us slammed shut and was barred, and there’s a troll north of the cellar, so I’ve steered clear of it for now.

* :raising_hand::
  > See if we can rush the troll. I liked the look of it's axe.

* :thought_balloon::**Checking the troll route**

* :thought_balloon::**Inspecting the troll route**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf50b711ec8191a96986c289e9c323,gAAAAABq31C9GtG_U7CFazw_jAys7ah0cdlxCikxP_9aL98h7pE7Rq7Ftd9r8bRgYHxqOl5oLhQ8lrD-qMyhfSKQ7AD792uB80-CsVGiZqk_XaIZQToAr_nVUCsQih4hY1FCeoWwkTtzZ1FEvTltNHLYFiLNRNWHnRo2iWr-YgwcntLibT32Q9-grzevZMgHCYfaVzaD9jg7q69NC5EXz7RvL9lbPRJqWqnDZySx8W3aJkFwqovQJuY75lvE4DzTdwNo3KzEhB1iOYX7U68GVMZl7XN-h_wtu-oYeq3CsOkLljFUuXvfdR62v3Zw5drSr_qvex859_ujPLBXmmW6qfCjlvZQ4ZFIrljSsG3oPeKh6w8-L5iWrXbpICc46LBoRig5es92xpf1MCf07JAAe4ZtbKr5KrR8OXbA3H9thSIsUyx0QAruItFMne4ZtNwV3Oa39esn4XUFoT92NzSE964ZKQ8rjFnaec30ago3FOutqvF9QvuOpv_K0pUcAjNfDDrzWqYdtbdNe7IbLJEiNwvN7Vc9TTjmk3U7PEkktw-gfqTtW57wp_SyqYAxFEI7ChlYrgYZKWbvD9dmj9KI3NuMcq_dOEhz4OSE_kGG3Djo7WIMWnMH5AiaH1vN0ICKpngk43zb6RvKbRd3ogsv7e-45HrjTv2c8Nk5-lWqJwGyrDf8_8zT82qxS_zP0I3kcYZoQo0SIqJ7_5jQDj9MdMSg-NvUEgKHFKjNUCOQi04zKvYjhHxjv6wj4UM_ZZeQM67uRILvWvyFWWgnEasfSyfqVLWncgjPFY_treIK1mwDx3rEKsYVeQ_RdfG4A4G2qNY450H9ImYGdEbqU8a8aTo2Xqnb8v-rEFsyEcbB3QPmj4rMQUOxU0SrvUgsUqIWVe8x9yMld_LtKkFmoO9G7q1Jg6bA-_CXvvDY1fYcngM7qDpjxFtdd6Pi1Sn2Uqm34iJea5Bkp-D793Okrxxx0sBs_i_FLwEh79zTmYDpuAEEL3_CSkcRoOa0nYhQvGww2mKRofcRNA-be5KHlC7WmIhtEFZW4MmpoBM6sKcGxu_P47pb4S6S2bxWY4wyrVl_6ZUCNO_75q7b9XRT4o-GCTYUhV7hLkWMzvDRUkKOPMdigGFwB4E8JpVdnL_x1I5VpgsO9bHjnxiCr9gxYmsXMNWKuzMKlX7owl_o4NyMaoJwgaECSPSfmTH343NXZZmCp89YlQib7wV7EB_cP7yug5yqM9Ui3fcg5RhQIlQ6CNzS7RkBLv_NGmhsMQPK5wTPb0FBqGtW2VBmxQcIP6kJSGabJhXLscvMqBm7c2n2e9De2AxrVdyU3CYjVlRxicqoeE3l-Y_8VBwtE8qp_V7ewMhiJxpL8xF7goNh311YVN_fw0VIj3dfvfQow2UnkzUlVKdMNf4uToBeHeNvSuniTvUxMHpS-esIWuFGhauRlDwds6xn2nRQkg0HhChpFu5U235SjUdcq-it9m5smvmYlD1Hl9fOZYwYzQ8aDXXXEfYG1ncvMLT8Su5El0Ds5Ihj5hLHdoWfFraMiuPNr5dDU8xPKFtlLsPd4HGjNVnmVu_jpobV6vhnHhBcB85Cjdk_eo6YKplrVeBr9SBBEetTfGf4uwIPfNHc_TDNcczKrOOAdxXhal2w1TinQPazETGfjgYmGWnpqVe37Aq8KNd9zNv6lijMd5l4hGkafaEDo06gL7jUh-j_Wgmxgw0JDXANEx5oauO2D7GT9Lm24AskY6vzyDPlPMuXJf-JnfS9BhnidfU7CNrlPkUuBC-in5pOXvKQIFLXYf8vCYHyo5s5RqdVqHA2YxPN43AAiDEeChlKTPokPLgCOtD6LmKzb_lP4W6eUipeZMr__cQyqD8mG5Bj8jOTeR6g25gtJ_IezJS07K1Q2yD7GCTUwUUz1AY5lESXWYFs3Axv3EopZ6kK8sCTxSpI-ohbt3gjPJ7e8Flr5754YBZmQ8XPo5A1GFVd5ExKbtL84SEazw9Mjc5hbJDhCZA_ycLA6zrBrgojrhju76Kkc9v9TIlx1zb8l9ME7b0UQuVbpEA-wED4oA08pimuFW10-42tVG9kFFGxwZjnXhvyRs_3_InoWEGbtOe_1CWDhABC19M-PqjSQVIRvk1XIeYtEWJZANoGvcmREhUwqe5MFsYyJgX0bOr8Dvb2kkl2PJe-IS5WTaE76MId4hLDZPnYzQiB9XaaZ7VfaknCg9zB20TgfQ3y3XiQ3vBAKSBF0qXMz_up7IoJwpwbITO-eRoFWlUUUVuBvPEDcOoZj4CZgwxM8BkXZ47eNoUL5RfMf-MTOqVR2iu6PrPWq_6hSSx_RYzeWg7lHy9GZXQUl-OG6gN0mQQwzzQ4OtnrWVF2LeAPYy-omDZORcQ-lMLtOCjlDnqDTideqS3GFUumFBpAQp1E4r8OZw5cPra94zMWIDEeOMgMBFYqAzUIn_uNvxnjQTJwPIePU2TVPdZeXvPiFRJ7NXXKiqfMGxXUllV9FIfTs0I1LntJy3z6kKgtBzPlFicGBxXSEoTJUTt2HDiJ8qAme7G4iiaBrmK7km4e3x3s2ACjWszen7rdpC7XAyhdUc7rbo5HXaLmLg8ersIhN6lxM_uumX8iENEnw127cr8Rr9kzm9EUjA-lnPVBsZnPv9-C_bIVhb8yrsk7NJLXRgjv8MpFJm_QCy1fcEF23zoWDuqN6mYt97e56nmxO0YoHTC02FX5PmvMgiOEgvyUgKRi2SHdxA5P1v6e4q9zQDi2Ib0zWa_p4lVtgwNFNzRyvvu4wuSQfJyRVqhSpdQUPabDSzR7NR65VlX1I9UMGKHhdD3jIBBDJX80zN4f3lHlRWydMNQ6qEn2eI-zqBkK8yc1p_1OZzvgnYjgLHnNKBdRzKVlyIkZCFAd55FRbdQR_lJtQSKzr50hMguNinlNQT8ONeN5Psv-QVVteyhgyx0-4-42vTCyqJ7WiRTotyZ6Fk2dpGjv4R_9rv6pf3F5EPKhCx1F60g7bQQbOl40G_UdaxwltjEAdl6W3iY_Mvff9G_uQbguVAKmv5Sbaorjn_vwpwQ4mdnCp7NCjmK8CTyfvY4P0Aum3_QBgXLk3NG1O_EvcFVV8WaOB2_owu4ICkjnLm7N2oAD8Mg_-Ly7N4sPjnzKLrg49jOPKTKLD4Dv5s6sgt_t1KicVTbcN_utkeoXAsMQ8I6ixaVayKanWy3zebhW8vUh9o4VRu5f6yNkGYe_F176Az311_2Sksp2ODzbZ6HZ2zKK2UX-e9khlMrtgYGhyVKRM2ys2V9pv6iUM10JcGyu5_BxfQNl_fCLBgqjrRufSyps6VCkmZiJdsX2TKGWDpEqbFi8rbBRwEPqRm0JH4hz-jR5CNghHyqGt4nYOaD8YaroeRe-81BxpdGz5vDDfVnO9GhtWnFGeztKsrA8yU3aADr8V2REXYsf0t8FY4s=`

* :calling::zork,call_e2bdbee22fb04f03bc34c97b822523f6
  > * command `"south"`

* :scroll::call_e2bdbee22fb04f03bc34c97b822523f6
  >      Gallery                                                    Score: 39  Moves: 25
  >     Gallery
  >
  >     >

* :green_circle::call_e2bdbee22fb04f03bc34c97b822523f6

* :calling::zork,call_fe3cb6b4861a40098d21c15f43daf43d
  > * command `"west"`

* :scroll::call_fe3cb6b4861a40098d21c15f43daf43d
  >      East of Chasm                                              Score: 39  Moves: 26
  >     East of Chasm
  >
  >     >

* :green_circle::call_fe3cb6b4861a40098d21c15f43daf43d

* :calling::zork,call_55f9ddb55b2246aeb4de2e6c89e4bba1
  > * command `"north"`

* :scroll::call_55f9ddb55b2246aeb4de2e6c89e4bba1
  >      Cellar                                                     Score: 39  Moves: 27
  >     Cellar
  >     Your sword is glowing with a faint blue glow.
  >
  >     >

* :green_circle::call_55f9ddb55b2246aeb4de2e6c89e4bba1

* :thought_balloon::**Heading north toward troll**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf50c992208191a447c1eb346c12f2,gAAAAABq31DMufrtpsce851mYvbv9RFmV2Hs8Fsv4ADI3NjWMDnJfefZu3ba_TSMl_n0SDnANR5PNAVgltxN3EeZkgLHpWBGtbZXdXzh4J9BE4_o9AKx8uRXC4Q1Oe73sW6qrcvVCpz7E-VB6jKiluNenxgHxwwjeA9Xfw6gO4KYrgL43FMv0FXBURSwjXz3AsuiDAGnrWUSjAPq7tyESk8TGGWxUGRsvyDjVjPJIo0eiKYbnTfZcDrxzWHzX94mS1iZgofhP8AsPbtp7l-n5iWJUTnUYV0-LbUi_GeXRLb6s9xhAnCV_RWXsMeiMz81XdVUZ8ePlHPAab66Z9DoTxVmbORkUlx84aM1_vd-M9s3c4Vj52vA_qwVUV4sh4c2-x9ArmTOBBZDerg8GaM2EBaXIn835bim2dUPy1KCRSxsiY2hWmNab3FmDTNIt8WdCr915K2AF9ZdbBq-0KGSf2CDz4PO3SzZIaUMXt8cDqE80unXS68GjOae66WEbhYXXCYGs6CwaHrXEE4306MdzmzQO9kJfWBpyZYuF8IViu9F93nrCZW4I8NblEWN3WZmrZon1fvuj07p_eBpGw9-oYMywpR2KxF64IG3ifcuOM4HGjK_Hinv1azbsHZUbTc3z4agExlBr_qCrsLWQ_lBrXa7NhB4-WV9E3MEFmAApDqs1mIrZV8qDrCYDb9b40tvzZHPFNcylefEMAaBeWmIUVxIVCXtgK8n-7xQs0iiWdcwvIaWF74Fx7d3qAC_gycFrBjFBgbBVL9C6-2VfCmRbFZbT0qUhIphzcsbTud0cCfQIzL4QaOeIIqc0uVr2zJ192Z_XguET4I0OrnDoBNjheTY5d2g7hmyXkpZ4I81W5htLn76qJeJYf2v1FoCD9lcHogeCwXjQfiAXeGW16qDcqc0CebbOse84xYTnIviBBvee237mGzARXpI6BzxogJIElKC8yTHc4R-27sVnzNS3KFse1LjjA7aqtMQqQG8uiGwmijcVXu5uilSo-HWnlrL44NLdIf17i8aVUF5FDY7wVNO8afn-p-FpyJV4mMxgB9OIslqyFNAucYtXgVO4jnt0q0w4xxXgyQ1fMJH4oEX2bUaNJeWTFCEt_BwXys1ADkzPdiI0lUN0s6Kbvc5M5KFbdgvr8-i-8JYxh_Yo_iCF_dLeGz7L11dt-Rs6uEBmcTQWCRT3O8Y45bpC9lpb8z5s7fckNY0LspTqvV1VSR-hqRxRQ_rskGvLqloMS_UNcPre_X2XtF8xxKzYYTDI-MjOFfNHcJu35gsP5ckdIxR_5NNmflhephvhoy8NLsDGeN_9_eMzA1Oc_UNlFuIMYOJ4aqSUegWZMQnPT5aTgaJvl9k9cTZe4dzLcpB6adGQ5QOmOVj1FzuhjK3ZJJx1irvPLPanWzYFh8Mdx4_UQ0UlV8EE6C3j5CrzHhNIFPWFeNazUmS2Mdet-gY_f4tEU7qG7e6hdxY-sinJTev9Cx9Vaz0dLnQjEidvlWA7fTr0DHbVx3KbDphWAtpJ6VDt84xuPbaqjeRsc3mQGzP2AX2rcKzkBRguYaFwXcwNnpyct8jgCk4xEclHdgFKr6C2EzROXQ13aFOdCyJmkQSkSgtfk1cI_yDi8GACrfa8ehP8rfqnESbPmTWr-qgWIL3ysvHpxFQX08GUt5qbwMlsnJ6nuFdT8NFosnrnOCxnzr9FDgMIHrszEGfirRgMP0CDn-QUiIiB1iN8ntr4IN519LPnLMZLpL95WI2WJ8WXwx9KvGjQo5BCA7jQnBls8Adw1IWXNtBks3eLYjAxWTBum4elCRBNCva3aFIBQIF6lPuNBpVrg0fCI4kQRafBINzIdmGROdryt5-VBSCSq1_PF9CJPtpqBYTV6k0LGyvtmxLkU9CQQYP7DhcBso-Vb_XUJa2FeNsqaG-T0InbIbNm6g-gFXTdiiqqHD82TVPjOPxElI1ToUPyFWWnTL3LcvxSljACmpBLpzNbTWOvjgpmfctstQNdNMC5THDxp4mLWv_QCcvt9iNr7iyHA7aX3xEDeS2dbyylcGeRM4OuNR4MuBXwD46xGlTMMNxsPeSskhb27pdEECq-KkfmZfvLgW00ihc4hJTuyXcTyspvnChzSGHbyZ9DaWa44RW1uf9ikeTzzYf7-awUsqufYSPbUBGLyJXRB5rbTrcTy_J`

* :calling::zork,call_055ce18d4680499eb676626dd3ec8db2
  > * command `"north"`

* :scroll::call_055ce18d4680499eb676626dd3ec8db2
  >      The Troll Room                                             Score: 39  Moves: 28
  >     The Troll Room
  >     A nasty-looking troll, brandishing a bloody axe, blocks all passages out of the
  >     room.
  >     Your sword has begun to glow very brightly.
  >     The troll swings his axe, but it misses.
  >
  >     >

* :green_circle::call_055ce18d4680499eb676626dd3ec8db2

* :thought_balloon::**Invoking sword combat**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf50cff134819190096042105bfd6e,gAAAAABq31DSwELn6gSBcDyU__c8c9z9Cgi8BCD1mXzMtEyX8qZhA7ezHFI0U4Kqli1gzxyp0vlFKeHCLsvLQsc2euOOlJApF7ZdFogXgb6bsfkd1LBno6ShH0HNElujjinaKuPIPQpnKMSE5mbsh76HTjTrMQ8T-Wuw4Z8ER-VzRnvQ1EOmNT7KSLrk13sr6O6sHM6RpCZHGB64LtI8LsNUb8EJcRCQwo-zAP-F4wwBBgMl20CM-gu8xvj_2mKtmSHSf2iqxJLa1jno72raCa41vLVUA0XdfuuUqWUdSK7ZEU9_mfD8OMGYZDqVl_lz8toFN7hVjYbeV3B6AUV09yB4iULB5x3eHJtclKJMJx4NCiy0wbbJAYtXpqeo90dBX9VUge5vmXHk8nyZlDKeK92OGVexnI8XhYo8BDfIcrY1mKA5en4Q0t7x58qwzwHkpArE0wfhOZfqzsUFhwza1Kbf-CrXhUAPE3KDrEKNHaVJ1EFP3y7gErxVqdYSZweGx6gRXwSt4krdO2aJVYx4ICZIjheXwl0cnvNBSKXTXUd9ffu3_cpeb0we9kfCihoGDucelv-5AKeRr8h_LbZLr4A04NboL1BKJaUdcjgFW3iEVfgP9AfHsab56QbZRyZm3h9omPRkXkrDgO7QTHvxZy8i9jTXIvVbEnp5Rva7-MBUtwCmWJsWdIh3XBiJGLpKevfkUSyXeBr_xlyefwmEKBv6ULZnZSE65kFkd-ioY56cE7KJRbjNqWS4Njjc7-NSe2avww4wz47ncKSE5ZRti8esSz81ceSOmwKxZMLM8oI7_qNIoq2Rh0FvnTMMmNhOdLIoIpt5Ii1I6gdKf_mP-8O6DGCeSzclm9MGumBopdiHQcCHGndVXZvmVBldr7E4hDNs5HsJiqVVqdHFK9qNvss7V35Le4f6cvNEmVDeDCAD3UGvx70c_3Rc1w9D8fQz6_WIO2c5lT_Z2hLD73qWPrVcl5I412P1mSxM6926yNnNgdjFz8yfl7GQFGR3EkZqXOGg4FL7bJf-oYACYtJNEJ5x6SgrADR830v0-EADNAA2phbrbqe1Pl4i6z80wkMxIEAg9ksdIbiIQ3Pkl9mK5oPGXEeN30IhTwsNWk00k16NEWs27teIBEZ1EYd2_bCm0yacdiB1h37cb3GRqtKew1xNRRoarOIpfo1JK6awGAznJkQ1WPU3O-JWzvjmoBGjwxYN7UhhAxMPPsc4e3m5_rg6HMdw2VuubAupip3SlqpD-HK5PI9TjxsTil4mUsa7QL2JE4t8fbseHhgEuO5q-iCy2_8QgtZTnIvuZYkcvE8AXOW05I9xf-a7mR8lj7_yH6sY36bmhW16KukIr_KY6xXHfCojWcfrhVz2Tz8zE1r0xhwex979Su19s_FfAY4-MhmZXd19GnmPJFXV6rpKIwtNFBTXeePmUc02HMMxQNfYkv8b3x9bpAuLqta-K72UKwy2lWVIJoqflj1HkugrqNhllyF8ld0vT268sFibssmbujoaD12e7JK2ppw3h-kldLtN6SJJBTs_RPmLIQMPZFQkvmXPfsAD6oJBRgod9Z06IAsCHslEQyVrlVY9kmM_eDjjgfu3WfbzRp1DdbuchFJm2JHda_yCgeMXK8i6n2h5qpvI8BnNkytvESG6wn-tfhWQKW4aA5WC`

* :calling::zork,call_d087826ebaaf4977a920c8daea4f46d1
  > * command `"kill troll with sword"`

* :scroll::call_d087826ebaaf4977a920c8daea4f46d1
  >      The Troll Room                                             Score: 39  Moves: 29
  >     The troll takes a fatal blow and slumps to the floor dead.
  >     Almost as soon as the troll breathes his last breath, a cloud of sinister black
  >     fog envelops him, and when the fog lifts, the carcass has disappeared.
  >     Your sword is no longer glowing.
  >
  >     >

* :green_circle::call_d087826ebaaf4977a920c8daea4f46d1

* :thought_balloon::**Checking whether axe remains**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf50d666388191861a416a0d98900e,gAAAAABq31DZWGnvGebP6UYUBBmv0y4JJIsA50O4DwE5aN1yUUdCUkFdNhfrmOQ7hc9trL6VXOa8PqFTB-sAFqqH4q_6AoQFYVl9L-ZYU2NWrjXIpoZw4xKauARa-sQpl89ZxCJIwUjuCzXhbz-_NaQMUWvd5tyT9NY0EQobT-y-MX-ns7J8I3AULIYdWCjfXoGx4VuJ9mpMTU4b8fRIVyXmW52_0AAoQqw2-BAKDeh1xh0R6tlCYONB7_-DzauXsyDXohAfCBQQHeSQZeyp6DbeLu0mch1BX-w_EdO1O6DeMGqbvn25DD0x3rgHp9WMS2W6CzRiU7uKd6U6SCdF4IojrflvX68QeFVOfgpPOC8Myng2L_yFRGlFd278KTfzs33Nf_XAA9d8Ba5RCU-I5fbUboi9rtCh3zbjydM0kchlUWixjlnHy_KdDm_C4xQevjgWMpgl88cCySpbEKsBJA_0KEnPL8Nv9v0wpmogNwSsuhwrsfdBeec1WCLK4I5qUJNxmAHt7kdXm4uP5Mt32UgWSBQiCa_zgPOgHDav-8qrrTCiKwH7OEo3gIaDx6GpiRfvQgEPr6hRPaCDPEGpNYAoBEcKhnFbasugML-siTndDFA2CWPxIn0EiE8RnBWeMjC3unLCMdoH_5p7iCcQNaFnJ6Fm-fLVQbLlhur8t1LBFlQxiU9MZO-86xL0gPlmt4eXJ0EDViYS-ckFm_nWGhmIDY5TPFIcGdrghzMrA2zWKa42hA0zc2mndpmv9qqdd-JVCw2Hy88VI7nFARSa0PGg8V_oLR-a2Fl0O2R1g7Mcaf1iN6Y5emFNrZWtzROaObTmKwm-Uk90mOlc3iW8EOkOsknOmMv6hJaSX9QKxkR0AEkca0x2CZ6petSLxPTeZLtRaXJpf9ZkNZMrSutBcyERNzpK8v1_i4EZFwkY5Wc3-Oshf4rL0U8zqstfKDq4nBm_urHgNDrpI_hwabYdfQ26bFTSp6UvvxzOliFKkNaDhR-lbMwyezzv7kldq3nuhuF3gGwUSBB2x1mpqaTc2VW0zYqOqkzMLtRkYoxB0tR6wMIovXKfIrLo3QKiSjfXO2KD2wIHpeB_IzfGen-3UHDC1clqVKCJe-wV3n7KKCy1duL2wWbb76CFKEDXK8xC58dyWTKUXLKocT2nPJ2Qf6EJxq3Q_v2o4J2xcvvqiPUScD7Baskc4hF4hC326EAoozq-B0mE066DXyy-mieSNm-PhPDdpquithPdb48VYAY_gcjMjDd8KLeh1SR1vh90TtKoH9_iyDmKKk4JZVmnhHJjXibYfOnBSOlIRFnQj2C8s4_VsgrgyAe-f5A8LgR8ckb12KSvG3YqSRpwTOMzqwzdLIm_yYokdXHYRvi42HRPU6vCgwjyWTTkzl680Y3_H01LZ1udEcVYv1nQudHPfI3gOz8sJX1XriO_w2_3OeydKJAVh1t_F1cQD7MwKdfjJAJJMEfLdmJbcJXnH1S6y4fV3Fr1n5XuQTJeMeLOv12sTJ_ug4kRpMKou1udiLFeZEz39NPKqCIR98WxN5iDgSul2oBwWvTPXRZn6lMLwcBud2fV0MZp4eLLLLz4MU-aXWpzuV6MhSLJ1U-SdIJe-BJH9AgQ2pSHjiY6uIC1-rMtJJspBlUMsOypPQG0J9wbgBEd6HhDz6mNKx02LXTsr1_8mVLhmnF_Io1QTrr0da_5gtKzU7mT3v4MaERnKRnts1PLq9abiYY8CXCwPyHRU0mdYt1uHATrQdOdTa7BnEyM7aOsfhKakImK4LWMQLqCUYbZRTZWeu0_`

* :calling::zork,call_e7c41f88863c4ee8911f2a07aa8fdb01
  > * command `"look"`

* :scroll::call_e7c41f88863c4ee8911f2a07aa8fdb01
  >      The Troll Room                                             Score: 39  Moves: 30
  >     The Troll Room
  >     This is a small room with passages to the east and south and a forbidding hole
  >     leading west. Bloodstains and deep scratches (perhaps made by an axe) mar the
  >     walls.
  >     There is a bloody axe here.
  >
  >     >

* :green_circle::call_e7c41f88863c4ee8911f2a07aa8fdb01

* :thought_balloon::**Taking the axe**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf50deb0648191b781009791cbd1f1,gAAAAABq31DgzQYm_7U2KJ9dRJC8gqOSWHGp0rt_sHhAaNhKAqW9hgoXGmfNdQgR1OxK-GN0grfc-ORonExr2D5oruaDGE4i90-jOObWft-ZlNqrOpDT2K1D9ApDYSyycsEH7yTGGeROViNVCgUuoWNrs5cEBbZCcLvHF4cSF8O1nUPfJirrzcSv7Fcger5YXSw9uvZ4u4k71_J2zhmk_iTD27-LCavX3i7pf2ETB7xYmBdCXE7_uE-GE5oNyE1gtjScbKigyKx6NrGDyyvX9RUlszG--eyJlLS9zZGtQHneu5azwSYM8pQcl9u0EX5nS_PHpPrEeM53D0mbBNbSrDAhgu7vT6c9_xHKPOZ1Ma1Mb6RNJDoibV7RK8GhDkVFrCYhhNZ8KUZlikx8-pg3z7uKipiVn_dnATs-yR6aDth96sR3SExrdSqSYszaxMkNfXxNtE03ygMCQufrhOUO1vRgnswl4W5uAXn-vIRWAr8vXtlAep7xk1DOMq5ktUwXP8UtGp3gBvwEA4BTTZdcTa319sTL-uiubosR4ilXTrCWpLhENTeTqdrmXVQ2A3ncOzNQU3pfxwws6e6dr1VSva91BIWdEAKeaGWluVjKJDkNyQgrkhGV4IqZSsaUHRmiIBalpzElBuCAUuQ9KDW8KSsLQl2SuXimeepM3zz00luDQtnEGRAYBnt8b8ZRLjmD5puKKLYVTTyIVOqi0txhy4HyC3YOPMTaLSijcevfbk-LAOa7m5C0aW6MtKRI-u5NIAqDuX6yH-UEqOXtkOtPLyYK59nFlqR5S3t-HMzYaQac84o4OFd2MHxh7ygkySaZRUVeUU5COKN29VGt_ekzhx54nHhXex5eia3jfcdANhWgI3iX1C5YJZj-R4kzQR3NO57gEeDyBgYsnasz0nfT6FpSg-IHUZcxtPo_a9gHztYclSB-vvuQ24sw8LU8tG1c_5ubXh03AbOXAR1kokBmu1etin3bhH1geMgK02DXMgKq73EpnrwH7le4X9zmbPKLWw2FdhYMDPxGmYTsZCtTFLFNAkU2M85ucVMqq8JuhkfP6cQQy0oSghZdXSEJqSUj5g8QAYo3r4XbMX0g_BqPqiVU7MAQOldzQSCMFILrRvHL-5RUWaKIx3Bni9kxduPbvdkMQNFnCguhEJns2rcEtHXYGqK2KGQAAWsurTvsHHy8FUWXje5aO2nnx0UzQKnCFWukDO417m9XLu170az5JjStXaDnKANGwmRJXARui9LyBZ8A0QlSlmO3meb6-TJ-DAwvR2JCf72hqHRwtH5PMNzm96OMlMPuh7Knen7brWIKbyFZk7E8RiN6pZiSgRLu65NI1lUA1Fz5yEslpiY-BEGmtKWuwi6HBpvrtP2FDMBd9-lBInoQHd6II069Vtjhi9h5zt_xwk7lWG2xWr-84L26w9HFHrxCLHiW2_VcnLNs4RXFEERP5GIEiCi76cLMwAV4HAS9yTBWw5qji-MgycfQ2jWkvmP_BtHLqw0pMwoDASJB2WHWA-2av7cTgTDP3g4V83PRL9iMiIOn8rhUdSJs_RrYah2L6IodaRsaJI-D98sx_4cz__E=`

* :calling::zork,call_c0f619cf6a264f99bae62edbe9f7efcb
  > * command `"take axe"`

* :scroll::call_c0f619cf6a264f99bae62edbe9f7efcb
  >      The Troll Room                                             Score: 39  Moves: 31
  >     Your load is too heavy.
  >
  >     >

* :green_circle::call_c0f619cf6a264f99bae62edbe9f7efcb

* :thought_balloon::**Dropping painting**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf50e3bd348191bbf569b56e730061,gAAAAABq31Dm8yVh88bi_vku2t0C_zol6qwcXjkU3_EgnTQoQKQyk-ctjUIPeaZ9IL1QGdJ7aN_d6Ef31v5rNUqZ5o3hzgCvmbFrIkOcXvUXrGTitvLBQFDpTtdxHAYm4VrLy7-lf47yyUzhznGrMZsXrq89k2gyiHuVa-RMtDo55FXbQKk_KEdQJpq4VtDs021ln-7TCe2GljZBQUPy85FjYHIkXbtamLFNY0frVZcLB6GM0sBV_UnMgyWqvkgjp9_MqIC8gQgkGnvzhlL0XlI3RbLsGbs_NfVf2Mloxrwv0mHGuVCHsgWSbT-DoVXFlSNILBkzWele_-A6KzUcvkQZNtcQPGFhNA4xqzq1QKx6JYLXh_nYiI0odvZYTorg0a1m_FEoWOclFtLCWWVQHINDGdH9fSyVEBG1Bb7lYypNT4Gh9G-h0yoS2Rc12wtR-uzcWSJgvBkFxww9HjvY70mf0XhfW3mi4t6IXQWbOo69klFrAyWGfaFrrsqKcGks2JWQtPDdPrjprI3D5ij4aO9-ov9FYCTzKcLJrus1_w-veVY5b2uPeAXzhSt-xFJkZQ-JlUJCLQ8XF9JmemIMLfFNCjTp41MZ5DIih624MrBHnGYwxYDAjYaOtv2al5v-NK9MKeS6t3vJmAylTnMS3AJc-JrYtF6nKcXsI6f-EiKiIziORGjA8XQdpbYUBoguXvrbf_Ocdhwm4X6nb2IKxe1KLrcsQJbyAI545-mvzSCVtoEYXk6aGLaK--NuwAODbnRdXACBIAHbR41gSsR3BbadM99eSv5-7f9g1ipvbxDNDlZzJiF4pNyUF7hx9hsq3IN3lW5rLeCOGM5mLR7chxuIznBtv_-aUx_JRH4nkKA-ZzM3HvZDlQoVIjGJsyZvFnVBg4ddZgME4V7AbyTGiL56Wz2_-lfwktH8Co4jkkCEg0BxZrRYCYjqrh3WjbYUSrdv87brtVbZgt09ZcXXEwzFt8_qoER1BKmWsS-rakKUYltt4R-NYF7t2tCFULs3ChZl5-MOWCSXCKarNsdaSp2hSD97u1puZG6Y000jdyvyEO0_mfSjrbk-6RqqdsUiODYAgLgqvN2ghH7Kdm9DqwiF0jKE4yvsoE0DDFoatiCU7cyeyABfXFuNEpmdm15xwKNo2nwU6KuKa5a0luUYDVIxTal8Jetu7H_QGMRiYWgEPejSHtUY2x2hFqeM4vYKz5zXUC25D3y2T_qQmbIngCiQdwkC0vn2dVyyaY4zQtxYp3QpJcxHmzzkHirB_IVqbEuJnYLEEBH4jSkBjtHCBsFN3m6cjGyhJY-OaWu7pkITcRnZ7l7qojTj2QxONN9mq5KXfw8rOWZoGB5YJz6pLd-28ORKev2jr1_DuwvfkqjpZ1RXm4mHcXPvH0Md8VbzHXJTNxkZxGg6tZLqqVDBgaBNQcYyF0ReBoaewBYhv4Xr5LGDjlaQZLbNTlzhoYUbZVIdHgZvkP9tRdB3CoJzD2TZ5wD-e4XmwAisB3PnFyCkwj9YQhxGfQIOPC1GghjghLQu4gefDAiUribyqbqU2zkcZ_1wBsM-T-mtwSJ2ONm3saKSR9N0coLvSqVmgsh6-r5Gus3Jalv8OMMShQK_ebypLQwLWwEhMqyY3ClVPFMz6WIu3U3_dvWoev_SG2ActNtDPPUY0gGwVGP6GHcwENZEZoz0Cx7MOOFmwxJodE1TXVryzf1PeFuxp8VqfGgJCopJwi8M6lZqXCxJQT4CrOw8otqK0VjBQ0bCo-wFjrqAex26xWphvW5cxyeAwswOTw7Q-Kgwr4Hf`

* :calling::zork,call_db718cb85741497bba3cc63a833e48ba
  > * command `"drop painting"`

* :scroll::call_db718cb85741497bba3cc63a833e48ba
  >      The Troll Room                                             Score: 39  Moves: 32
  >     Dropped.
  >
  >     >

* :green_circle::call_db718cb85741497bba3cc63a833e48ba

* :calling::zork,call_1faf05fa0f9e42d296d8b82f6505a280
  > * command `"take axe"`

* :scroll::call_1faf05fa0f9e42d296d8b82f6505a280
  >      The Troll Room                                             Score: 39  Moves: 33
  >     Your load is too heavy.
  >
  >     >

* :green_circle::call_1faf05fa0f9e42d296d8b82f6505a280

* :thought_balloon::**Unloading sack**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf50edcb4c81918c396a8fd34d4900,gAAAAABq31DvA-jGrCvSiCC9dUtJisWEMXzuIMYtjZ-5MwHzOMRJbPE8AfKb72O1vcHOJJIsEjYA7_iPTYl1ZVrrapFf2T_iZv-4FZ0CFpRMkNwjGvc0ZxV5VUsK9xzfPcqpqN2WWkt236WEhXbwpOxhm0qyuZyM86h5LZI-ICtQTbVn85Ial34ob8J0rweB1sKt7FtQ7nm479QvQESIzMgWGXY4lpm7_Y_uPLa4sONCElQyUNEPR-BKFYXwVkKTw1bxjAfzE92M1jjLUXneQAJcvr4vqPkrD7DJT_g6BAX_IqiIf9OcWkWLGUQ419J_Qxt2Kjzio3IjS-RFmtcRTKRGo2E1JDUzHgIr6zSFNoUF7MjFVmZxxiUQEufD68hmi_x9MIWn3KwsKNHYSrAnw8UVSGnNp7iTI2-t9zBLm__6GFi7DL1Yj_UPN4B7scys4eUU9a1Js6MjZqnIVftm6bLX6W7XZHQzmJFqA1vlgcVrr9DeNCD_kyTam8sr8PC56CTLF8L6dUYrmII_y_HSakvZikg7JRV8K3Js5_NccDX-ukVDQRIVct34rmuG7Pf8R4EYSif4wxOskPuiJmmAZcwBqJpG7RM96gyi06wjHCkoMELV5Fmlx-LP2LXeL14WofDbMS8I0782czq1EpBrZQHj55zR_ZkNZe8u_yQ6GDSUOklkNxGW5jhAN7JRJUEFfp0b540vTVlARxdvLhsiH-HFlmbWhjEad7dS4QUGlS5f9FQdu0o8xj5iXy0JPskkKi2xToNGPfqshWw0zFaxfuh_n3I1axXC03ViBlQElD2XjtSfLrdcciGXrpHBsXakaFjpTz0TdiP_Bs3-LucFJUi5aYnystQpD4fMyeu399j76s8kuHwsWGjhFfhruq8cihlKTgmAvVqkjsPxhzC3rO9PGrIs8pJKVE7Z92MqQZGZ2ldqwgpZ6hQLuQz6uZ4tNXSFCoZCRvGY9FbaH_UlClXJRudRXIT06yE-c0vcEgfHcEm2yzV3jbsIXMv2NszaI6ew-mLS5HGGY-BJ0cp8HAZFtoq7KBTyMVpAOT-QlmMl96VPX3_4Dde2F5nOdifn_teZQli7zeuRTYBtgVyh2vGx7hbI55i3gxfX6UR6wsiK0syWroaDW39xwFw1lZZiBpz-OmfnSzKtdSJB98qT_zJASqJzpYTYyqNYMms8zMFjfZGqkuEeXYKsr7lfbWVF5a009QQsndScceCsdjwYoh5bAAaGep8a7kWmoehGcKgJQ7Z7JCJPLJ2IncaIA8jhYla8i-soIaEj-pwZQn4V5dbzfxNo12W8dZwSrSKcs-z_Lm1oQ2As19Aefl-QSdhiwhr8ozN0FEg5ny_2qpYEjF2XjWs2qjOuPDdV4CN6Xn-IbtJYqCMNkR9pAQt1KLVgbDsi1vhgNtvq940gl8GS5aLw8mzWfiX8OTYuyCQ_-MNwNlAchoZ4QGbBf71X_evUVei5_UgEguu5TaSk7lc1XT1kqWxhJ1Byx1RzzI8vu84S2V34MtnhDGe7PRMbU9W1KTLGq76kofEtTakRQ-hNtEZGf8RB4gZDsZzjKUUwW-dqRXW5KKeYjEmtnSJC3lkeTajw57FTFf1OK1vIuKU-5_m8-U7z7vVKXG0uiENURij3hSsHoT-JU_ZLNx3An_lfTUN9yhlKthMOAw2dI9amvnUZ2RLVTUJQnl2cdzL2PRK2IQTqHL-mZHc80Jrx9ycl4GD3XVYB7_v2`

* :calling::zork,call_f4a7e55438ad4a55b1c2405f1d447dea
  > * command `"drop sack"`

* :scroll::call_f4a7e55438ad4a55b1c2405f1d447dea
  >      The Troll Room                                             Score: 39  Moves: 34
  >     Dropped.
  >
  >     >

* :green_circle::call_f4a7e55438ad4a55b1c2405f1d447dea

* :calling::zork,call_0fc3d6db8e714ceca9cd61963d6e17a9
  > * command `"take axe"`

* :scroll::call_0fc3d6db8e714ceca9cd61963d6e17a9
  >      The Troll Room                                             Score: 39  Moves: 35
  >     Taken.
  >
  >     >

* :green_circle::call_0fc3d6db8e714ceca9cd61963d6e17a9

* :thought_balloon::**Taking the axe**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf50f638a48191be770765cf565d70,gAAAAABq31D44wimQKr7deh44K7Phfy5OmDUTYKDkP8Xv1kMkPY9iiQ-X2g5wmTv3fiVMWcEyqOudN2P4_ETEJ9JVUeeDSUj1-LGZG0nPVFKVGAYIOEfRPuO-6ARe1mtcBXb-2WxQDED5LXiFq1KXvVDEWZGl3HtbHfY--r4weipIBfmOLwWE8_UH-lFN1p5aUDHu8EUcGD5jaIGERoEgbn_BZAJkUNaC7-U01e9RAf5wN4x4u5TbqJD_hW2uhE7jY_L41lCuqjmgeQsVs7C7iHQaVilh3dg977FaYNJuCKiGuU_oeod4wMoQA95vwFd2FHotbtrAoEWFD5Fc_olg7GvRLNWC5PFGBCMcieM3CvxKMawL-DDQTp-cowx5qY6Y7VW3AlYbJJMqUrI1TBW4tofUULpHRgIAJNlLCOp1K_VKeQIF6uAOUSmVk-tHMPzQNSJorOshCwQCcrwuA7RyLIcttxxr2beHdQSCuz52DQCtktzU1tXKCVUvQBReWMTsK41TgoMPNjYRgCh0ulpW7tg_Kl1yfyn69eclP24sTEiR_53ziMX6M648TVxch3qWRnMQOthJBEY1mpm9qw5Ov2CxmoIYdYxPJzKf9J127kB9Vv_fV-Hq9RNE2mYFMhFKAw-jZepghswHcCJPDzcgbufpZtKu3AMEksH8131TqS9wAEngcRNpTBHoXm0JCov8ydvMGp907bEaXVLTkrgVcomS9rj4beV9uEzbWyutcxEGPsxMhLbl1aoJIfueE-TQ6uH12VpWXJyk4ktvDann-s8BQXJSnGuB5lw_VpuZP1IDIeAl76yfmzE8X8Jn5VD2qbkWpcenZcdqIAdugzSJSmRMUQVOjAAX5hTeSbarEyeP7AopWWDHm7u_SgmRR-gf34tTmcR5Bff4pv5TJejbDDB4JvozxSqG-3Q_ifiVz20EnkoJ1zMxi79SK1kZRczCit1LpSDt072v4heqb776JHX2FdlApQQ88DoSpgW14KvuFIXi0q2Ny45ZtaDVAFT4XZzMIbQfjiQUdR1wyJn53Q7190s1Sa7ktCapFPRa9mnmzHQLLstelP_anx_oqZ8KoPfrDK6sOTN3vZ2W_ptSLDXV0UzVQNMK72uMrj2Aadj0XxPXGJz4vNSq32FPc7ocFxsLAbqPUjOasnpQp5S7SGEq1jujEZJySHZ3xe1KBHL3bnv720myUK4UVtr1W1XbcS88SYG4WOsqfr-rBa9LqK5MVYIfWEh_-Ekizxbcom6RpE1As4YkrgiAnErLS-XzJPgBmq40ZAQz8qEhfSMjQla169tB0nCOVt4LP8XCe62DoCPsEqZT1tuxzipuvuGHDgCkXVFKxgdZ2IG3utkGGnTho1T1dolTdtYPbZa_SWSzztAV1JB4VAx_MOYBI6OQfrbZlRBvtHHeAiPCpI89Q-RDs0a1YySW9fc7yuPU1qOq2fv5L8uljsn67LAcGGD2M67jFDqLRAb22g3sTMylv3G1TE0O_6aC8INdV8pTtQlYPZP-fhktU_7fwYX7mWomSqmDJ3woMEA3unKcwS1GYMjMSqKkP8dARDOPghx9bfre24FlF_ArGxVdW2g5KAamOuoxgYY7f6vEk-wGZxkCSfPc5Y5XRjd64yPAAXyLZpkOY5wUiL08frQHfpvuJOY8R87of0gSG4QkBUSOIyBBD_QSCO_x4kYspBvT9y9UlWS7TQhAJv8G6iRnpkIXW4kfBOLaMUQdUqnpOl8y1sbk-xSsiB8ReBJx5M_YfdzyXRYY4mL0SlFtLBMAcomj2l9p2-pks4BtCBYtV_Jzs6PMAy1p6XULaLQmaqEBt2Qhj-jsWuQvGP7MQD0rwLWjqyiOHNufuzwvJVoxPJqvrVp8IKy_f6znsV9-w==`

* :robot::
  > Rush successful! The troll swung and missed, then I killed it with the sword. Its body vanished in black fog, but the bloody axe remained. I had to drop the painting and sack because I was carrying too much, and now I have the axe.

* :raising_hand::
  > Maybe the painting is more important than the leaflet... assuming they weight the same!

* :thought_balloon::**Returning for painting**

* :thought_balloon::**Dropping leaflet**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf5116f6b88191bfca06ffcda219c1,gAAAAABq31Eb7vqoQmN_d2Lbdi7WByRIyHyaAsQcc1PprrZ5wpjQV8V_kPEH33ePCS3klijD2_Wj7nHgb63ywg1R9LlI53OLWxEsL_1hb2bjSJH2R7TUIawdkWOB-qhiMRotgVG3PtF8J4k7CFspOOVYRsV3XspHSrE-1cXVZJlsg_mxULkfiWRSl4UgZBUThaXEO7mIz08otww1SujZyrkYS8ug8rs1ir6yC_5meQpDu11N25Ah2akfDRALc4bZ-e5euiqrUtCxEsLHuIsJ3Z2Qwa3TXaId-cORij6BfY8DFm_y70ylf-ZZtGTiqPV3K4DRnbog6tXBuf13jotxD9sSoMsTieJFUQgVKQUrZjitz3HC_2saOwet8Mh080Yb4Q8GPpFgDUbvgLnVPZOL3B96xnP-rTZhSADvoESNUOg7VsQ-T6xZHPkN5o353emCmdc5h6s7b3HyKmUZZmIPevWACIXE6a0ru9I4W4z89QBOOf0scSL6M5e2Fgh67uzKK--2KhfISlbPdWpPf5g8hQepOBtL16XVAKc_umRL_WDKk5JBPexW83Wtl2g5bDQZBNpqqvMpWnH_T7kllUyaQlFKxqlfR6-hXl_Td8wYbHDRbnh9nERc-CGWZp7VuTa_wDR_bYx22NYmeT3knGN1bqCO6e2VaTPoxl08sXvfUlpo7PRslhIEIvRuI1UnAuLBml7s3gV7rSQs_vXb6ADK_N3OpZirpvftvSdDkR8NqLsLjwRdZWGJYgLhsIEUVIwr5MWNedOLHqZsiq9fDxwaDsYV9VDlU06e1USYphMfJOQJ-F3ZRkExHIPQytrP4_GRJF05jJBJlQj7KewjfF7BzQfgKJbaE3_dF__sUGxx7Mlr8UP5LBHR0WJQx8oS8lGEC3TGMTNy6_ZYKf5MQ7Svn-tTJOKGsWXdcFHvhZCLl9s4PfFSk93MEbPWl2hsbd345ihz3k2FhEiMyiGgpwrBF7GLJdD6QUVFbeh3ske88K14IlMF6pUJUxOHNvtBlDDieD7Yxlt3f0d4UxWy1XVuo_rRFT8ewCR-nwfncd-9JW7AzZ8iYOxFB_7LrbIb5Ffe7R-s2izvsOfPsauTPP1nXSjwiGBp-NSwRx4GAcPq5DVSiq2pHvqrPjVvyAHRUtj18bccqgBKnZaeQ_cn0udsPd5r9aOi4opgqk4lPbYFkB9OM84Zs8ugHkqiiHD5GThhbBIy4wIHQ5iPLD-stKxFbavotGh3w3F424YnkvMqHrKc_vtDjPa3Q6bRsEzLx195L3pHmEk2MP2rBZmzF0JQmri1_inKlTnCWawN2DufhI6a3cn2qg7AlorXXAD8IHrbY3KvrXmAPOECoFS3TWh3ySU5atw7IxvDc9OYj8UjYtTa2XrPNK7tNT15p0FSrJVeQlPG5NKO2Qmao5NQBZwS8FSXHi_KB7BfN8oePKMXtT31yb778_DcMXLP5CEFLGbOYgE0GNlDK2hjKwPd7o0uZIvKB3urtOG2FzC6hyZwLZ8hkOuPwTA5g7J1lcdN8tv68rOhr8nqE3WIiz-OtTYPZTbVqWN8dBSOvD16sJyxH-Q3dsY2YUBpL7fJY1bpqRwsZu0U8PUQAHrW_CqMrAxh9zFODyedT79LMv4Ww69VKIDl-e1yVXCUuSrZCL7q6OnynNx-m8gDAflnwQ2tqUHZdi1hkF_oHtFpbmfhaJHmvSkFJ9XjJsM5N4Qsef3Xy6mcbsPNNxwJbFGrG06sT0wjBoO00szsZTbry1xD2itaw_lVKfDXnQ-t7zJMiT73MGO10fAvuxW_1R-7Q58lhZLyavmqYsc9Chrml__ZM6e0Wyo-7bRAsBcEQ9M_5VjCHaJUW91THMxXIJaIF1MVlRhy6c7PoLproeT4pY04nSBp_rvlequa6UZo5pMlpfPeHZ0oC9catDSAo60wP4H1Zn5Qa_lal6SSTwNsuyjU7XW3lCVa1l6AxvZpTcqwzhdcyZr4slUscEuuqSZimmet_kZ2s82z8paLLmjMksdG6oZeYIp15qpRTnMcKk47A9eCwFNMwR7kAogdV2uw_5MvwLPPK9ZOHi3eXPximRTlUpfXBIsm0ZXeNeUOX4yaFzOlCYx7BYOESJTqalmMMeT7gJqOrhpCgmVBr43XH4RAyENuJ1QF25-caP21XdDwZQXcPLXUuXqNzCipEVfTyWrbLMEY-JcN1e5OVNJn3hlz5Q-s30mXF420igk7hCzOquolpyRIBv2bScSkMHextDSnAzUzthtPgYwqW0UHT0OmwB0wPaXbMdVptxag82EirezAvoG9iVB0QRQmNU7UDFc1O2dnEVHVdkE0LbvSFKjQ_sq4eTdige90fQGGEG4h8MtdBqvT8V5R9ZushwjhgQKtC-xwxdCJP5nSgvw6MzMJkdhvMoETQvZB2wnpX8TXcbONNFKHCMAkrKep235OKBScptMJ6Y6rEHKIYhJQxo0Lgiy-5unfO9USyAKwXH-JjJPBn31EUCEm1KTHKuW5sJmqGA-jsMVC7a9IteO7kbI8EXeCqflxAQlxEVRVHYkHN73W5UYiHyrm-bhzgpyftIi5Kq9SGvBC1fUPcRHru-dMyGkKyartaD-QjvpBPm9BUyKL8CP-wsLQ-FmaktA4DZG1vBxjoQu31gHGG81ZBZNJjaMCusrtByRUfWy6-mQcFEe-YBB6tkvRj8U7FX1gki5Oir1I_60G8L8x9xN2m-hZQjC1SdFQHKwcXdNfc7-rlmtkU3Ad-HuSgfiWSryYVr8i_A36TGwMiZE31c0eYBVTcF6nC-nZUTXtt2V4Q-41tOzvBbG9fGvWTOsc34jV0LGaUrT2zfOxc-JZr9U7mVMc6jHjnPyYFnO2WCnEn05ISf-zFxOaUAQe0884zw6T_acG6tLQDn34_c4ecPHIxQ9IN9kYBA4geRtPMB2qrBQLYiBp6wvJLZ4v7Q5HfQc1s__gdJk0-WcMk_jS2FJzjmCk90SW0dvokn5QYpWrH9m5eorS4b37m-nZnJNIJq_9uEFyuSMNN-lBOiSQzBhJ6aFyPu_Au5gN16taCUPauu8bJKFO5qatXftWEBeqDwY8XEs9bidsZ6uot17KxhNoElBbHgMLI-09r5cLd4A2PP4B4lRodCviFgz-VsYVHdMyDSDo3TX3Zc2jpyssMMzdU0mGOXe7IxlW5hfSovZ1ajVPOLPG77HUCCcwtmOznsZD5O8-q27QqiN87s8AHwPKTJ6ookHqTxcS4eL_6xvprsFqRJG3DlvT7_wbQ24nbq22XR-QieWDgajm-VcfVoA6B79g071QbWBi6CpYZoS-w68NlNR9ClCYs8LX0T65589CM2iRFN5YvrXmxBgEZ6a0Y95jVff66_gb3VzqU71_K6b9BUlAIV5HglSJvOQYBw8EjZJzwtPvtoyBdLvfSj7v-_4FXn4pw9_dKuuyjBda4rogbAZhXjnfgoFzKrjCUd4F3vGRCQKYkINYwS5aZB1filJJCmh2Qpd2Y3ArxXi11o6x2e_XRNSPZ1-dC2hd2292g4h8fAglIe_vPpCEAlmP-i_GWm5RGz-O4RNjWBCL_ckJa3zz54wV3bOVFcVITRK66tZNDbPMp6-ae8MiPz8lMldKtSmJ_B2ChNqQVzUFO3AwJ4ErKMgdK4-ccIR8MPiu0jbeZ7CNfvpAd7kL3kz2AUmUDIb0feymK_rUqQhPbTUCOK0MrQNRM22T3m6HOMRDJY-yuvptaFUa_hIsP2war3mJjejFXjLJDfzkdd7K9Z8iTtrBny42yJk_bMZ4RWlQO1NX075sgTYROSkp-UNmh08oOG4TY8-ayACbMsMYPiPvLcvnsV08ap3nWELq6Vwt4770qbbimz7aUVE7jngcmn6gKsw1ZetLWYNve0ZJF-uopSLXMU121P-GLF9A1HWWP17HV7hheNhJJjA5zyjS78WrBYMKZaWKwtxclzcyg6ouEF9QRY-FEtdBWyb2W78PI_8XhSRSZFVMC1e_082yeg==`

* :calling::zork,call_e987181159974eafb89c56552e9ae387
  > * command `"south"`

* :scroll::call_e987181159974eafb89c56552e9ae387
  >      Cellar                                                     Score: 39  Moves: 36
  >     Cellar
  >
  >     >

* :green_circle::call_e987181159974eafb89c56552e9ae387

* :calling::zork,call_3811f112636c417fb6af89aec7a0c14f
  > * command `"south"`

* :scroll::call_3811f112636c417fb6af89aec7a0c14f
  >      East of Chasm                                              Score: 39  Moves: 37
  >     East of Chasm
  >
  >     >

* :green_circle::call_3811f112636c417fb6af89aec7a0c14f

* :calling::zork,call_c47701e09ae841d1adfc5c5ab132f8ca
  > * command `"east"`

* :scroll::call_c47701e09ae841d1adfc5c5ab132f8ca
  >      Gallery                                                    Score: 39  Moves: 38
  >     Gallery
  >
  >     >

* :green_circle::call_c47701e09ae841d1adfc5c5ab132f8ca

* :thought_balloon::**Dropping the leaflet**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf512588bc8191b68904aafeb16064,gAAAAABq31EncB5YmUvHqsBPnIy6Z9m6Gtk7dn7aFDV5wEPQeGB1IAoFDF2ZEAm63_HgMhWx58hKQwDw5cxs8MMS4lQk5b9BGD4gQMICheyqKeI3uAs6td5_sCuY2do156knd5rSAXy61jKj-xND6VoQOSbvfQYc-m6PTDmK6B0gj2s95r6JDTpUKiW4h8vlEHhgNSvquKquLz9aRRVj4ONMP0aicV1SFSfHFFTiNmrVnoXI182aKgu7-qWD3XzrV2rBOUk9wSgksWTjjFeZv3VWVGVI-e4V7YCmWH0OexUdOARgEfbGGPJwCgypUwK6Wx3nZ5YssljYlNnosAs_7Kv-lwOTnOF-P7R2wDNzsLEQ0rKVPuVhZSVTz2xR1NRWXCIK6ZtqOPrzBxTsEXRD9G7tR1xb0_N2c9SUmttvTpoLaSUb6M089gr3MBgqiURy0i0omKieVgGzPpc-MmKXLzIHKTmw-Uxo48QnSXQpO8rxjNBtT1BUtlAd_TjtjUZw9N4VODfGEuawMdilByrPW8DYqXtcyN3TuBPZAG1_u2iWSMK0YFx2PfF2xef44YjHfCUvTzUbTl2S80elNtRSqV-S70gL7nGNjRFpOaxAg--sS19EFdfmbtjy29Fl25VATnW37tdBNc6JqZSyiYaPf7FXKh7hdRl0Rbtl88P0tCcSYePBT6UIweRaL0WP-YqclUnWINLtRg8ht3ZYDrAJctgEJI5h8gNpAmfnYc6z9dhT5GnGZz6GNHY9pKvMp_fC87NkQgDASQMGDpHARjqY14gvG30gAKBLwq1b_8Y9mILl9fNT8AAz6ixV0zYpLrJCkTOEZaEHzijJIFgnR2pRIyrwIN-DI1t8R9xBaVqMAxPHyX5czHLHqYq9Cm1HJJw8YRL3uv86nyxldB--g6HoN6kjdgWjCNq3kV_Mw2wfrEnVzvWEJhN6k965GqHo0MBS_fS47vs9d1qVD1P_HNV06qVlf8VQfcdpLlOX6swMaP1Io59nVEeWSWu9yJfNGAWGl4yt3AREfkRsl5HoW0xqdwkOc_jWTYoGW5ZSDML3cqY7639y1j8jGuUVbKGTsokMP9qKwcreb9BjynaTffyznqOlXxj7uvDWml6xp88UQ9dWsc_w5fCD5LFYjtqbwAH4YSth_ZqAicM1VrpepEJjKRcR63NS808kWjZVGJ87iwDDQIUYXe1U1FuNJQQBKFYG8N_IimpUTM2snW0XfsBXOpZfak3QY63pVA_VYldnJeHR_sFtwGV2P4Etzx4jXmnx3ZAJnHmpRQsI1mFTRretm6Vfbg6o1ujGZrqrobCIBb5Rn2pPJBCOO6EwZ6rrnpommx5akkGcZ3RTRqrk2NmALv5ATmsAq-Fpj7TTVEi6n6kd23M1ZWT0-FIeScoM5PyMF9XEubgtNB9O-zHzB92jx1jniDZLf5H3xzGG1mpPD4AoUDtCsDj9XooFki9OLiEKwr7Mjd4ElEepghAgy9KAV6DfHY2VjTfFJsUHzV7ebzoFw2GCU4O3byingSan3v1QzOhxjuOxhDJSV72VW6XOeopWp7VJBc_mlUe-J_r7ic1vMjS8hThui7KzzsJCn3ucQrU295J0yCUWaYx-MHhKenSMACc_Y_OMLEpw371IzOPGNdof4xMKDIYLxZ1tOyH3c0wLcCRkqzRDW5DwdJaN_3CVIaZASqHNBvT2uyiX6SLyr5IRvmhUqhAPvkLqIySt6cdimQRWOEL7cgV9Rwp0DQSlKoVY5EeaH9EXP9SN6aynlbrhmKqvtmw=`

* :calling::zork,call_a1433a4ba414495785e04827e9c2cc89
  > * command `"drop leaflet"`

* :scroll::call_a1433a4ba414495785e04827e9c2cc89
  >      Gallery                                                    Score: 39  Moves: 39
  >     Dropped.
  >     You suddenly notice that the leaflet vanished.
  >
  >     >

* :green_circle::call_a1433a4ba414495785e04827e9c2cc89

* :thought_balloon::**Taking the painting**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf512b0a588191beb2d91cd8afda0a,gAAAAABq31EsbZJ-kcymAT92bow1uUUrrrqYcAbngNSwO8JcvaFxbows4JMfSWgDzRHQijBM5ta4ThZBsbLK0518Znhu2L1gyLBjxJBNB7ZwcWfh7uCebhILv2JJEIs-X77DYfwiHPV3xKS5W6s_1g3wFHlp4Kw_pjIVaEjX83Z4eUH-KlH0R4rVdp0v0wsMRa0NYadsmmY6b9_zlezPRX0VH4jFWSw7NYfbpElxOhx1jxZbt6dLpE8bWM3hLEtfhs9SYNfdi2YcKtewHah1m5aqyIlKkwF4_C0f3ZXTsH1Nh0vg-mIOWhLZTegSfx-30385zSFAcTgVVZifAJFmshrJa-fjSvu2I32GIdxUeogtrJr1MvdejvmUezRRr2blXQqyfUf0U2luI33IssGfyy8EV5_1W1lNh29fZ7NNS-45-JSRrpkSVnMf57NDCALYjoA5oneq90AcJ0TW8-IU6PMBthhKj7bqhy2tpMBx_lfDlKOyv4nTnp5tbClUkNGaHlJFRSwbk-DLWTTZ-nKqbuYeEtmkykRIQHwanhkCP-SAE7la8sH-68u0EQZQntdSnyjSXmEAo6-t5b-Sf3p0CB43UIkMB-_MWLqFEEongiS3fp3lnXvGro7BWvilhYrUJ0vnNHjuESUwfBdzBBzcwZgm8A9HoQ-a1Z-3eObYOtv_MtOf6lJvpc4l9CsPCN8FvUaI64dXdaEkvQfYYxyQ9--_dx69xFHYVowJnHiskc6glDrSN2fWfJAxuFOS3siv-5hhP5TjFG3bgZgsi4TghuVMe5950xFtMV4mxpRaKfVnbLSI0BRTVRztpV3E3OM31clc6IxQJOqTG70MO8tET37umJswaVH28u62xTDNXvb-4Hmjdcql-dxk_SFdJQJN5fVObRaUAVG97NVzICN2ZCBYnqoOX4xaVrgYv8avvH_eggBHR5TNiO6sHYkLkpd2khJL2WeF14JUo9UKvkBCK0T2cOccQhgBUjfWVQdsqJYNe9IgYZbtJwhMg_kdR6HSdDz6-J4ZknWYNmDA5A-P-uJpFckuGd_FNdijoiKnzx8F92d531MlXCH4VoUFPVjX2iPWTFNJcHlfe5g9k6_RbckVOZCvmH7eHbXqy9f-pR3HNLvE3rkzqbnlWmXMB43YNzh1VfTebc-WQ591_QVt9m5rEyDVFrX5U8lXJ8Bh13souGpj5G-Zik23PqRH1sCwqA7uJ37BX5Z8zlhnkJA4Tu8rXhsUPEIi13tbJkNpmGyIFPTqm47kZ_hPjNdXrtuO9YZGscOw5NaG2WAomttmcq5xdVeAabPMh885JxG_pTPSXMUXWF0CWVk5oX4Ags9DlWYTNYXpqRywTEVYlm38ASJJ-gyhtMEpiypMc9CZc6NR2HlIKsQ_Q5lCytY-AQkK9bGRsHaV8znheNRQgQoOzdiX07gNmjsLlWernGlfufw6jzsZGJZqTJf63RWYGW6zILqiqRbZ3--J3ltuhhdoeXYKoUg4D-WE7UpZvNk69boaBzfmDWnOPjJTQEmQjL72yL7ZyiKZdMLOTLpWy_2f7L4hqLURlnxJCpEsKkb1Rs7Bh0-6ZJAqQDg=`

* :calling::zork,call_18b98f3a66eb430899d226a5bfa083b6
  > * command `"take painting"`

* :scroll::call_18b98f3a66eb430899d226a5bfa083b6
  >      Gallery                                                    Score: 39  Moves: 40
  >     You can't see any painting here!
  >
  >     >

* :green_circle::call_18b98f3a66eb430899d226a5bfa083b6

* :thought_balloon::**Returning for painting**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf5130888081918c8e8279b0e7b07f,gAAAAABq31E0HsSWcAA5XvK6IGjTMn-7RjJJ1OubvpVPQODFYMCDqwedfwndGMIgOLPq5563YR6c7CS8VXS1UgnbCE6kfatAOYZmu1P00kfWVumvgasoK-aCJtNxYzdRkiDhL1VNscBrwR_LbmBlTX9DIaiu4KNC6fxXUBwCJWKtXcZzrVW_zctRna9fRRh1gamsJXUNFdmLc4K-JTIaM-HqR8MYXkos6_SY07WL5ngUXOThSaFbsNc7j-mGpgzqK9_RCz8W15fIeBxsyTJ9QrbJ0x0IdcBg3Zm2L8R_T5cSIQ9IXi6vyP2WjAe6yGoSMEpzA-LmbS2tXs1UZrxnulWnORI3vBqYqvg77TOmmsuo4IgLDRkeDS6dgkZsnOC-dWbUXMV-MT0H63MqeXb-CGsQfnspymhBiZ4fI4hDJqE0Hz7F-_S-1ocF2R45crPBDFrSFnMuVghVRc04siWmktnrrRT9z9IOHaGyD6yrdfpFFAduWB-jGp5E2VBzm4kwSoyJXfy9lBoX93HONvR-lbQXyL3CHG6CeBBiUa2twAWVcZzraP16c7c88-kDgY5Kb5S4OBwcpddZfabdtp9MsRlA4BvQ3KpGUtlvu_eDjrRcVsHGfCr0QCfhibMfSzlp7ge1PLC74KCO_DNgxVzg_6Ml3VWdcrLrZyXhzhQhXOgujlUqeN878KVjRTwRhBJmw_eqflTzUf4w-q1b49jCw5NHWa5zXdMNwcZWUb95B1e8d9XCjL0xv1Z1H466QwNDLOp_4IxeFhn16xJBePBBJDyhu7gX5GqOXxtP-EOMC1mOxqzmGE6vNlkcdXpNQg3NbyFt3LbkSbEdKR4NvGBkV-Q4AGdFYW00uAnM8m-YEOGUsI0OK-h02clZqg1ZxNx1DUIhrm7epyC9M3kvDDsglgqjWo9zBahjK0FFLGlFqKJi7Z96K0eBoZiHiJS4YVSbasZYltRFCF4VctSWHA54urYpdr-86PyCepnkBJ9w0RZOpg_JVP0oJhEwzKnSzomw8LUP7C0avOpMuRNZ449ugmnQeoMDEodHRSWuh20U3Kasq9xLRdskrws01OTL2c13sw88R5KpiU1XPeoosNzC-m1gG72S-4KPg_swXsM_F3C1kwnt1CjHj1dtS-qtG5Mq5QGioqNH_s2yDWA8p9BaLPl9Y3hhQaY_rcNJ2Tp_J-AE5VKF2WVkzM12ZgfXJ1C6_01ps2m_3vyjpZTaM3v-xgbAMBYJovOArFy0ZUGV3pKL6icJl_FZ3QtbbAkzgndc01tfOBqObOrPc4Iu0mnDCKS3OGPcayzOUItG6M8AMYgaCu3Z-BE_POfWYIshEsAXDd-9KJ0GIyw7GKog5mQQ1fZ4x_CeQAjAXzm5HCbA0Dr6Dw4GEnpcm-nDpFLIGhs-OYzd7U241EN1g3Z6TdC4v39WesYZQDXAW9X1d11x5OIwple7JBTQXJ36uk8ELP8QaBKwelniupylT8bYok49kA_WMspw1hM-92uEwBjlsXFA1RwNExH7OCorODIAXXo1H2ch5AGJ5ESCFrr7DLmWSxrOWgREyROzU6ucXFIQnejbLgo9lDLmlEZTTlNJzi4QEKiaV0_0_E30N1D4-YMiOJrCnQ_FUBi40lekWvm94OAyNTTMdVKjE7FPlC9fBuVfRsomekGuOBJiaa3BgfxPD6K649P0c6FXfWuQSFUZ_zEXViT2a_d57rX1NB1jUCRPX4w0_HFuxyk3_Ac1VsUeht4zTmW-_C4C1AFcUqrdPwC0n31lhywbzLZu7sukklJGqXBStOHi7U2679Gio5FzhIbf_igOlZ7NK7BJ-9fh6iYqQfUziCGs8RhNB4bQYNvkFwht8OIeaMbvUccd9IHYYovs58Z5q3lcPUhJsGBJcZBN5K6xWanTcaxfNp-O9BIy9w3xv13UZyJ5SZW08fmnIIwOXABejXLKkZZJa3QxaT76f5SsjGHNO4uiI13mWzjXQwetz1GhN3qZgTIbT7-pLy2j2jD59_U82xDWQOxyx-D_-K4-eTOilqUrFUAaXXNImA4-fSyTgeEHW-Hy-gF17OcvBkZOly6X42m_egDBsecpEBJxqpHLnrBTu_jbvSUc2SF4nybfkhlzxiEAbNrN6XdN-MmZ8-DCZWDF2t0p-cDDqlZRBBXl3NRUkamnopxJgw0y23rTfgy6LvzxEaJHkNIzlUzyLOMsYjj-2KvBfJG3NS8-dwWMC6OQZuR1gwvf_U1SoaoQMtvawCHdgTEQzY662N-QKUsITYUZHUDXozYqw2Nc3_8oCRXp13Ey_c1jjFxt7VxlDt2ZznLMTXM5uK0EELRlCkHRsy87RR28h9qGjAkVcuRtzrsWbRAaz9i4bM5-xWyt4Nut-mj8NrDsRLS7a2QyoxXaehmaWa4t-xgnfOCz2RT6rNFlcCvJX5KKIEcCfT2Ir7FwUP1Kvi3QQ0SXpYZAzOphjoDlo2o2Zdsk07U65ivC469IHnaaRRuFaa3cfVU6amqdVj601A3n1ciWNYw-3ojXgjnoQKvzylwHYAaKQTMvKKZg2ORNTJCECfsYEIsv5apN`

* :calling::zork,call_c6fc6aebc3284796b2be7009fdbe3b3f
  > * command `"west"`

* :scroll::call_c6fc6aebc3284796b2be7009fdbe3b3f
  >      East of Chasm                                              Score: 39  Moves: 41
  >     East of Chasm
  >     A small leaflet is on the ground.
  >
  >     >

* :green_circle::call_c6fc6aebc3284796b2be7009fdbe3b3f

* :thought_balloon::**Checking leaflet location**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf513a78848191841bb405c5e62d43,gAAAAABq31E9tLkUeqI47C84NrkrISRDMLDbQPRAu3GJdZ7JlLCFNhPWTbLgzOblcfO5OkPiaRQGjINBulQw5u09iPUs83S7uCjQ1WuRGsSgg6EPD5yz-9sb5sQcl0v06hcAmdXbboxHcw8tGdNxOc8l6qeaFlMHRHZVmAelQsLlEEGJEN65fKO7-7JYBPIGsZOZxX9FgER0LpMlVpq5ZQhUD1zgcqrFdYeJUHLYTZUazJFTE8T0qLe04FTl4J6Fb3l0Hd1YPU0mr37HNB9jIKybU9JSxI3KBbm5ohvf8jC4tq_59U_jxY3GJLfU6WUxwHsqE-kP5CXhY02HiVmHP_d8A0I-gH8lo5cHus7BwqhBRAq7Ou8i1RaCSpGlMB1lEx-Mc9zKoyLfqcLmNS2_ngtLPBUVGZjBL4S-8kKbPv-EFbzAhXrvMyXrCrlB2Tcr6MxYBBIeA2kf_FZ214KHZsQ1yO1rKe91tIttVdjr2ueYwQoRCTv0ku1RTwjOE_KSFq8s3nGLrFlEx54zDqH_TLjBkNB1UomKsoc6V13Zh4yX0DVhHx5UTz8O94wCXTjdItxQCJhYPRS-pF1L7eLZh2B7WfgdO9sbMpGTcFXd6IPl0vfM1y0uuecANdd_XjRqzE9swtrHIr43KLy6yuv5HlWh-XEJVM3-imGP7u2oIUQivMYUilIQFqc9syXXzW3GUxquUYdhIrfX_pNLkP_TlGdccseEoAgffAZv_OHCmC5DKNihrF0B6pofWIo7PsYnwiyf4cwN8R7D-9apjPRLCzvxBLRUpjZAyQ0bBGj7d41w6PtypGFRIJ0g7fubQwhapOqfFG9TuHKYbgPk5WKqyyaibgfacfvz_UecLiPiDxYeaxLZhEtwFInyPGk5rJZJiFAFMhxMZXVBusqi6gYQaxpOPfxim__gabbGPhUh7ZU5-d3EVLk8eFhz2DO2tnHq-alifS704rC0CmEKLnwuLZD5UAW4IOHk-0byg__b7va_dlbW8ztAS4ZOZHv01v1M1y9j5H2_62DO-TodFLDfxMyl6JP8krvbUhiPPvxctYOXZ12jTfq8cLCuNgf5h6mvwDQUYgc3irBGJKWEq0PiO6YBnjXGPun4dhqqypB21BrP8FicOzLYtNhYZpnU96DRVc0TAvfVMCGIi2gLZTTrIIxD5si6fAXtaFmL_rG771a1glKYw44SfxAzQVAlsrVU13v789ICESAmda0hBsuPyJdm-cZYrqAYDhj3Uu01l3nn0NcXl8sHqxhGE3EW7AwxqPVyFAr-LZ9rGi4kcu0ygWJvb6ecLqJKS9f58E1qo4tZtJjlDHiAb4e8bI-oXVhw148p_EzBbvgJkIXL5hhCkqetHplxjLoTQAwjII8bFtE8M7FTmLyKQUvzmwijF2jfQqAZNv7gx1b1K8aSNdALzCXbZMigNNqQ9av7HpwM87Z4oPmPnLU4QciYDQ-FOlfQQXMTef0IRHIsTMR5kONDa58YVMT2jEBQg5bdHKsx94bN-U0K-EZxIr6zOTpALzj-y0MZCWpbk5IsgEbIXH74YDz5RGEBSZWRs2zNZWULHhnkL663OdcB4Fi9Qkdwhfa4eR4f8V_AnPzYa6ClGnQ2JmWwhe3hTi_uOn9d9Mfw_oKW_VjPXDNO71dXB9_dKCQPelwZMlp3eWV9prHdwmgjGt-nSgkQpUSQAiPMiTR3B8wGjzw9QBdSkCocC1K9E3S2f-ZzMlXPJ6Xsf_S0wkg8OdddNBI0J046oy-Oqv_RGuSLP7nGCL77tzm08Ve3PJv0LrUOpUxui6NB8cmmDxYdJ9Rw_ezzlP5SsrrLW-td6Q6oKadpKLOo3IPoz6tga_zIaK6xAmmpqNEiDiiNqUZ6vbNsBMxcn4ppJ5oEwICizugDJgwuSq3oU6m16Mt5S2aic4-2BhYHH-T5KKM1eqyJtE4Ahq48WnJrGv986qOYuKT2yIt7phSDBDLx09uEfBh2qVkG6jbQAEH_MsxTj4aqXx87FJFwIDEoezWGez-rkL2wiEX6AGL5bspi-jLnNW_nDusK-dV13CQag1fR_ew9rCXHs6BPmdFBxKQav3IXsniaqlMFhtzOJ2RqHSDvbEO83dqe7rsSfpz1jQSGiqVA8r1KG6hHQ92czNF-XVMB248CD0BKmC79ppr8OQnMxqAp1_hvMFJj0H0JTrhj8RHMQCpu24HTyFbPCGlhl2QtR3zZ7dv0K267xOfY_MzbDCFqlsnqJTF8l47spTdysQkpQ8PRc2Oowalm2HOy2IyNgNQz4WBpsrR3eSU=`

* :calling::zork,call_f8f38def1ff04c5f8087b4a0bf4f974c
  > * command `"north"`

* :scroll::call_f8f38def1ff04c5f8087b4a0bf4f974c
  >      Cellar                                                     Score: 39  Moves: 42
  >     Cellar
  >
  >     >

* :green_circle::call_f8f38def1ff04c5f8087b4a0bf4f974c

* :calling::zork,call_73ebe299e3c44014bcaa40bdbd35afd5
  > * command `"north"`

* :scroll::call_73ebe299e3c44014bcaa40bdbd35afd5
  >      The Troll Room                                             Score: 39  Moves: 43
  >     The Troll Room
  >     There is a brown sack here.
  >
  >     >

* :green_circle::call_73ebe299e3c44014bcaa40bdbd35afd5

* :thought_balloon::**Checking painting visibility**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf51439de4819195f2ca7496b1cf9c,gAAAAABq31FF3-Td6cY46DPRHQYJaSUNdaPkUL4wIjq6-XCM0ctRTQj0fly_ENZuJy0wqMr4st8L792zqMYDCRBrv5IDrHoK9DSJsoLn4S5O8Yg85CB_R-jGxRHvutVsvqDgLR3CaHHQ1Zr5hFnEG4Sa0LL9HgusrGxD07g0jZ23RvcP3Gq8LxmQlkCN4QUGCiiqXXtJxgXkyoqfjSuzHzZWZPEFRWlhOBZbg6HpcxZFn71033_Y1Ri2Z1LHIdj8vk6Hl6TRqJunw4K_1BDMFlE1Lbw_OQE6mDjmikYV4xGVbeQjfruzGX93r6g4I9FXxTqJcyflacIQ9SBK7f7oVBlOMJEpUqDPUfTqlCqnjaPXhl6Sr0cYEvAZiTVm7C6lNbQFVnRsvxlc-h5BK2clY5gxfsUmpLZz0RHfl3Ul3v2Q4FXBnpkFstTYxl-KdUrZrzPVm9LjU-E9-r5V0KDYfFqDXLYxaGao6QRoWxy2cvRGnKk0GoBOeeB8MKn4ObS8cOueb_ynXins5CLBNvKvwzoZD8RqEH6F_nbKftraP8b5oNw3-Jj-ZsMEMsxK17Chuta7Vf5CzOY0-40XmDj8YR3eOv8iL8D9h8J6u4Y2JCTYjPq3dHm7pOH9epuaqcjuxKKeB-NwsSJ0rfb4w8S3e9sHaWh-iCHyuZXDkeNKJpKFAmgus0Uezwz0PxlURepEOyqVS7GRqB_hEvDJb3_mOMpr8Nr3N67qhCpGSYEKNEG2lJdLamvKu6Lxyyp7FTDz3rJE3afgb4f3hCtaDQtUnc5Z-gGmdq6_5Lv81A6RbuBBRtSSt3c8hSeOkyxdSkwH8YUjx_flZWUOOHkbnuYFq1ntnlnaBJRuKqp1rHRRki8SBtVC1Q1TvakyI9G6gl95sqMyhaWz6XzFYD92Q5A8dpfrIe3tc9KGBR2YMPRAQBf2po3ydKe3ClMOCyObvaDIGHojPcs2__vAToCTx8SiBkF42X1NlXvO_zEvef5f1FIM-mcpAnummo_qFdpjUbYayZ1LroXjLhdFkWEd1FTNBfZnKtAsONvQvs2Kv3w4UqcMcPlZTsioUGVPugSxaXtPJDN_0DJPpoSRukBpHtBiLPd3rW3W37XuoeGBtn8DQOZPTwCUOH7lFFy0zsfjZHdugulbpkb4tyKDY_accDSd6vxxXGaz1q8BO8acQVr1OETTLRv1f7uKJmYjew8Zcm6ZlEbdevtiE4FW52qMDCDlEH8KZAMMh5JobMYkqyENP1rQmGgaE9j9MjVsDvkImi1ee_RVFQGXxcGU44lC3E_QSs1ZN5SfjJRu7B7aRNmnXm8B-tR-LGmXw7xgVPFG-qKYGc1-L6wqAnzp-6TB2Iuz_r-b9acCyN0Sjfpt-dBd6Mq77YRd43u6ZPTOWZ2hut9tSLZsOsAZN6PPRkRrxh92oe8rrvBRKSh-ULbVtse9DbgmpZGH1_BieZIsNNoaYWz2ML__HncCEtui3x96HUTVUGPCgAMavnf7vfNjguKgtDso__ccC7SmOkgWzH9wuD1QJl96kjlchnBUkJcbB8f3E3u6hudSL5yTzrASIPNDA9WtrmhhaefpQR-rSYca_XAbVViooGPxu3boQqxsMj-0TSeWtQhU1fdSuGevc26yhBCn30yvhCuGtj8=`

* :calling::zork,call_cdfc0788105943f4aa09e879e29e0f37
  > * command `"look"`

* :scroll::call_cdfc0788105943f4aa09e879e29e0f37
  >      The Troll Room                                             Score: 39  Moves: 44
  >     The Troll Room
  >     This is a small room with passages to the east and south and a forbidding hole
  >     leading west. Bloodstains and deep scratches (perhaps made by an axe) mar the
  >     walls.
  >     There is a brown sack here.
  >
  >     >

* :green_circle::call_cdfc0788105943f4aa09e879e29e0f37

* :thought_balloon::**Checking the missing painting**

* :thought_balloon::**Retracing the painting's location**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf514825908191adcc3a97eb6b710e,gAAAAABq31FQ0ey04wSpsVXUTvfnqa7Ev9Gxo7YR4QPzT9NzikxfLvLbZaGusSmSkauNvdVvO2DB7_CPGmGAp5Lq-u7Dv4FCTglVK2Q94pbqXSicVWe9qBy0Mb-i8G41d6e_14HfP738iZDUEaM9IrR1z_t9F739LyqCkLQf4Y-pMuyTQHHTavK-VRa4Hj6K0hczQEdUUSCk4zYrU3axsq44bAwhC21uNifJvPszjqI6IC63E8Z-tUNN-ET6e0i9s7WtRItqZ93jG1_nxC7FEi1zRdaENKdyfmtatdPrKeMjXYuylq3BxVzsHMmQmCG9GZAhqIlKvM28qWVzhtIWacNbW2YQluxjmnXBZzeUOkV1vIRDTqFHdsHzxNgcmGIeQ3UvQNn3zkW-b_2SXJqdpsjFfhwaywWvB1LjK88OsqEGD2DDjOceu_0Yb2gVrBCdmvIa90XXeO2Fbh8q7jJ_6gxvhzsD4O20BEVskAVXVFx9PVmHnXNW5uLb_kVwFvr7bvwASdcikrkN35w4a4PIZU5dEAJbCBbibC-GJZ2bIGyq8jFOpY926-NAL9cGqzn_KdU-EnIyy_L-2j2oRJj2E-R0UkVfpZt17rjoiQEb6ebay8azKQfFWKyMDAxCBDg5f4oufE82bGdMezMKYYG84MCrPe3xWc2FeQsez5zCqYkOfNi3z7p1BI5NqmsgK5ChnnQYMXEDWr_PAC5inPJD1AF8avEkQgg0ogwttTL-X2rb8Ct8uc7RoYJdAcJYBw36IWZyWA2EMyIGMG1TcCajbg8xRVFE5eUVR_51EIG_tbVphLLA7o85DUIhpVI0AT7xhh3aLVirD_tKEAXEllYGSWgy0-OkXVAdwMYc7y8TSHEko7FojUyvIDKTH32H38W7xmLYVrQr1BaJi7k7PsYGgoW2eM2pKbQTN8oE4v77LoR2abOrWFIwteJWeqY2xV2yml39GTvzBY-pqa59l5xu74twYMpsV4gPpSStDq2SzLebc7bAZdwIgOJvrk2UrqLl-D11doLPaBoEbI97c00nDepPE67LP9X7zKnuVAv7HB0YmraYk2a5zbpDVcjX-E2cVXqyybVVyVfpLO-Zp5VGVfTxncZartqutr5FAw0PhcNyRGBp3z2Y1urjkOwRhAWAyi5kPkArXDDfIEW4wSipBlFXOyP7AO8_J23WZrS2_QNrcJGX9ntkwOkEG45fLUxL4zJ9Kn3UHuk4g-vQ5bk-uQ7m0UZRm8NrWClr70ekC1QooX129iPK5_lCYsuOl7E3eq9t5DvFS5dn8OdyMGwlQbI8IpeMjn0la-t1eLxi3oFCgKsyDt2F3j8XsYG0fa4sIMQ332lRqzcXARtdzggEaDIXZ_n4e3DRveceNhsz-VARXbaXiLvgeBlgSCkU975lpogqfwDkeuKNzEyWQlE36A5Eeu8Xb26erYwAJHfZuE7E2laSJfuk_6z_EAPhAmCBdtVF2qdXj0HVgQyy4naWI1dokhrUCxpveQC08H5kuAHelAhv-UgQJMdSu_qK-H6xnbe2HS3hlR31l48fY8QyY8PjO1cvd65SMKGlSzhx_qzYiat3ZeZ3kUgPw8WIXisrqbCE2AbROWZBgIRI46tFWHCLI8Q_j7wiRFgHXuXvNhELurI1Y_KovwBDJAkhOPs-Uk79z-ULHIk9rUbmeFHinFITTEFmX2Q6YId_SOqNj5Vdft1LYIGv3wPqRnHZvSY88ybjxOtBx3OizZ5hH4ybkbnu7DmD8QjDBpVUZ4qufd5K1MuYOQIay-kj2fkaFBJjjBVsXnZDlR_RZOgw-wPctWZwI3i3_iS6J_j4GWFATwz0NazUE-mno4vDQ5eWsxH3gK9cWzN4YJr2GuN_PRRFU7NvqTUrwo7EjDBr60Ufek76X_nz2Kg-HaInWwUZkxKFRJFsoPMYdpAdSzZFSz8TDpMICDNotpacZDJylUML6_vuWiWnn-Bt-Ip5Qc9ecQ_iv4Iins4wZQxTxsDNT4kFRrPygmWD0a_7KtVUIRnvjub5QonGhRJF1UWf3LmdNgtsYTEg3uBIjXvehkz7DE4Y_xOmyucBoKWsmSfJNrPn-OMLVR1ICuOfBA1kA8x3ylBuqfMOyIakhwIHyCBHeYqgoqrFfQqHAAR5kl8pG5A7jsbFDNuXWsf3OIFTS6eoNFzBWqZl_dHq2ZEdfJOdjW-l5s2OkNWsZgk_Tf7IOcKJg6s5IQqeF1ezRTjALgUtaee3ymLx2pSflUK2qsLj_t2tALngxbR_RNXQmx_aC-I8lPL8IZHR5oJDlLL8_fgQzG4mWbl9Tf59Lcte2lhBoyIqKBwz2Vg2mxO6Z0j4sWQJgRgVpRCtnBE78g0hbDUUdz3aubuWJMunQUbQhcKSeSNgtKLYw9KissZkqm2h3zWA8k3FNkre8hnDhbclWZX7iQf1yAb5flnqAwWCiEXhTPdFFrvmAt3NQFlMLTYqsT2PycOrvfn1cIpEjYjs6ErdkJQ-nI9SEl9YHswaOcOOfvtywejLEecnajCSnvHSWqcFFs67kvMpO_FsTfAK6Q-YfkGyOXdriu91hw-lvS1k42jVas1nPv6NZG-DFbFgvQwuQIPkpiwOz8FmLiF2UV51WY0X38x648OTYnyCYvHgcSAFjn6M5OYmgyBExTnbDcNZqAHzbLx_dXpMZZCO-AZBMiJJHQivsSxDNmz0p0TH5ktpikFwPfZpG1EiUZOKl0PawS93GNZof1psgJRmE93ZaI9yTAs2sBIhadX26RTgrpW3G8dWbJxpVb5oXYPakjJ6LQ9FP6krwY5Uuu2Y2fnp8shTON1zafqGPfZ_dMyQ6hMinJzE2J3Dq_DHL8otlihvIAhrNqQVQdyXsy654QpvGa9PXzQPAJLwoXBU_HBjuddW2l9Djzm4JcC1pYTKinc4Yi_5OcDy7hVlCC1s-FdD0PG8XX9QLUQbUURwJHQSn_orkUQEAYjZ2h7xbYPHyV1H5w1OpPeLNKJyeHgXWusjg6WkvTRJ6wM8MNMkHqSvF1EUSG9YNo_6St8TGeMsRYah9BHZEq0zvFajNor3oba-fWm1QBQdx9FgyW_Ic62FgCEVHic5lRl8EhUbDQiHIpGLfy3y3ubLOaKhcemk9YXXQOstskYhFHOZL-wKZGYc9M0jKYDD2OiIwlXi7_kexJvwbLF7DlnKurPEHQGaTrx2XWGNnpT4Wygz0UpwCLUfQswAgLyPOesV45vWkd3n-pPSshbVYeL35hfrNf8puu3Zyetp7vVs-pcFql0Xob9KdzOF5FLt8UPsnEECZd24RdSQtvOn3C4HPnK3xLOqvhljrMfvHkfUkGposMngZT0khbPmlsHCjPmNk6ooFiFpywZeFmrfE_W8CnMWVfitGdEj_mP_1pgVFBu52j-iVtLFzPQtZPGq4YwANO0kY4oJtMAHd5Hs_ko6rlZtNZx86D3GUsZ30_H0RI6wf8BRBlTGpnLC9I6g7kbujaS3ROQ4TlP24EBIAzlu-UJwUd0FdEUCluJjccQM4QsEQ3Kq5zqXIr_zFvWF5sXUtdMZVTCA145zRyLXH1G8zFyUphKOWQI-ucRzEotwgvDounxIBMs3RWG7oUNkPBWPqA5OXlHk0OqigP0ykNqi8BKOVJDz6d_3TeTemIkdeElloy3R6YRf7QQ2cASNr6AA-wG9tl_c3A86EZsNyQogkQqw3FSeaVOLlENm2_L3KQdWZ5wUyuBe0Li32PhKkW9XZgWWYPdalahMGjJjNyvmoUCoqwQeTqShW-vLf3g-7nrtljP3QI2tNqyq0f9974UHN5W-ga1PlUZvVxj_mJ9EKcfHmOYop1BvU9iaxai1ClMbugSRTT1031blb8WaJ3019sJcrnLwc7dOssajgYp7-ZLYRxlVS_XGcNpisWR8TtCaHGNiUeo-9THV-y2-I4BCzguaX0jgyrTWX9-ZC_vAWWnXxUIflXU-YPkrQH_rTg00JdBuzy6bjK3qi7mOtAGcH7tHfzxViFAiftrbt0x-EuRzyhdr81lO0LJqK8woCp9SNlu7vy14xmwM0wxNnSSBtLRI2zu6XSOdlCT9JbBoKUo4XFrqpJQldiUnKypcErAFpxEQCnCmmiccdRgX7dQTfWjivFIGoYH4tDCzd8D4OyIn5WIm2ObMisZ5Aj3ouk7ExC5LCBnT536amaT4r8cPhSl7YAXHkZ0tDpTIn4BTrH5l0vPO9axQQ_k6Zau5Plq0KZn58aRGOhyil6CPO0OHa3_cl6D9m1lVy5-OMsPh2CW_2CYfK6Nbu8OojnmR9wx6r9wdtscgNWv51-DLUei0gAMoKN0_mTFAr2tQKsE4QsohK55fPjXCC-YLcR-sO9sC9y7NxMGPKUHR4PsTxmkWhBmMFDlUqQt471iuIAxlZpf1tqipPO1Sus8UCuXRh_iQ4u3l95vAMKQQUJnM3SezYR50Q5BDRkI0_NXsxpcN5WCcfzJuLdLHjRh70GQWyhF9keEngD2rl799qBaUa34ZG3I_G7gJpfpI_Pf8KVgalvb_Yaofgm4gLckkCQjI9Lf7pxoHp2H6ljkUzPD6KEBdqg64dJpxMfM3YuWHgVdC_dobeGqHqyef9bAd-oy0buQqSSquhfVf0_PrUGwlcPuaOkwZIFiX1bpOFjmYlPz3Ygabi3QstsNWnWj_WlnqQV3UR__pIx73oee9L5XLZO7qdhE8CesNYb0EQvKE6F1lTytwv5D8ZVxzmUdzAk8AXCVAVgy05C71uwb0zqGcTmAtPFxgCvNPU9-M8JqQi35YVTvV7_QXr2hvgVT5eBy0X3b7UMpEztF-42ue_HQ4DupAEulC_F9J-R2T6u_ZPl59WO2-Il7-VIcbLIL4BoQWAQJINbdAjZ40or81nLmQudHumTQa-NHmcnKQg5ZusYDFsL_gWMLxe6eTxzW07LyUctc7dKz7qxX6AL0TwX_lKS4clqHZQN1jItL416rkVz80eh9ezSKG_Yr6DcKbbpyDypqKSFq-wQEz46xxhSqYBged6knjoXs--frt4SlKLlTlqRqC0QEufDWuIC6uh8TmjGnMkEhg4T9NOPhJXtYCHsi20Cuk6VjU93rkK1PqqrbwZBHQSrPtLr1P2Qwg5ZZuclkkmqRJYfg14uqdq4hXaizg6_hxxj3yjee2kuSR_yk7yypafHbLhBSsUV8M5ykUdwMGXwRfGfF3qQVWgqiXiNOAHXvms5CQ-zbIys5i36orMvEikucMvmE0FVHJ3ZuV0rDtuVTZ4kdgH-LbkPN3ozLu8wdRWU1_QltQ-iLU8HMceSszny7DptdXh-Qr13mq1ayGWnGkOpU_b9gwM_mnOWMbZfaUNfB1OFCWaS04_hE_5fV5I3YgF8KWb4vNRof_HYNz-81NSiTLj0kwlwZgsCKDgfZcpb5gwlwAptj-h1Urjxk9dhFwMVdptdxiUyloVOskjX7NjuyehTUIqADxwl8IOARkbCPSvhDI9uecJbGhBc4WgkIiTw1ab6Xios3C_DxXHODwZXO74SsvxqXQkQHOgELZiAQ_VK8VngfvAoZglCmEe4b07fHHhqppKl7nYu55cxah7uiqussOXeJ2KyM8EfYgHyog5nZhaomf652nzDk4LImNuzU1FXXCVZbs_f0V76bT1xN8mjzanm0X4LwYumhTRdyMihx-WJ-Br0-jfNoSm1abEd7G_uIDFuOtzcS2yV4JgihCyw8R2--SjSSXDSVwYg174lrvvWAhwBskBRchN2l5Jq7omkPmddVnu0gFxeehdihLpne7qcdEM83BqL7RE33KOrlNhwofwFbvROkZrN6HKtXDTU1Cn3EAryiV5frqvtZNyqmqST03ZaaeHXn86Vsk62JaeW8t4cPdT1eSFuZpt6_i5jtPwbfHuN65fH4EgvxzIM1kuwe6s4FcoXosBTqNr_FMbz8dLPA2fawfE0i5yJXgIfJRTKWJ5ivpCnHvoFs-aO6XJiWZ8BdAs-r0tyE5K5ecvgGwgHq-20QjCCy5X60mfWsJZRsQaNtJxyQPPHA41_PseptVCBSWyQVUqWWdvVn532kqG_7lgj9__0EyWKDqmkGXvPeJiqDe-SGuoGN4yVH3UlzUSl5QaHPnvt02-NlTjy2ZCDyQhWvvhKaGQyP-hrM_GxxVWk8QRG7LQazXGU7dn2zbbnDJVkySG0jvRqdHvC3r0tYw7-kBB8rUm5L-BoWRBS7Csq6hpb-mXlkQPszhbQH6CIOqDt0lc5v5jjaKuoxHrNwE6xUPr6GyvmI7tQqarc74uLiIii5n5Vg1R9bLO7HrzJTiblb_gB8H4J-17YcT3EmDa94meIwREPVx0BEFCF80wIyXEnZNkft_OGySwi62Du0cZci-uVDcxWv7qA-a72cKx5jzOeYDRJjDgC3u4eXmVdp9drNCY1RgP1H0Lp3-ExOm8fszHkbXdSdaEk7pwTrqTQIdBdeUrUDkp-8GZGOvimrIPG-Bfb6_wM8RQC1dsQnuPC72vNWPcok6d9zakqraD06AcA2CMJY4_G6DmB_fdXCOBF8y`

* :calling::zork,call_3e351525cc924260a5947a20fefb4c66
  > * command `"south"`

* :scroll::call_3e351525cc924260a5947a20fefb4c66
  >      Cellar                                                     Score: 39  Moves: 45
  >     Cellar
  >
  >     >

* :green_circle::call_3e351525cc924260a5947a20fefb4c66

* :calling::zork,call_8a675df5215f48539b3b44172c73535f
  > * command `"south"`

* :scroll::call_8a675df5215f48539b3b44172c73535f
  >      East of Chasm                                              Score: 39  Moves: 46
  >     East of Chasm
  >     A small leaflet is on the ground.
  >
  >     >

* :green_circle::call_8a675df5215f48539b3b44172c73535f

* :calling::zork,call_b4d2e2c161904d33b39cf6a386c97162
  > * command `"east"`

* :scroll::call_b4d2e2c161904d33b39cf6a386c97162
  >      Gallery                                                    Score: 39  Moves: 47
  >     Gallery
  >
  >     >

* :green_circle::call_b4d2e2c161904d33b39cf6a386c97162

* :calling::zork,call_d983d3b783a847909c5cc0feb15b0294
  > * command `"look"`

* :scroll::call_d983d3b783a847909c5cc0feb15b0294
  >      Gallery                                                    Score: 39  Moves: 48
  >     Gallery
  >     This is an art gallery. Most of the paintings have been stolen by vandals with
  >     exceptional taste. The vandals left through either the north or west exits.
  >
  >     >

* :green_circle::call_d983d3b783a847909c5cc0feb15b0294

* :thought_balloon::**Investigating possibly stolen painting**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf515d01c08191bed5f17eee73fbac,gAAAAABq31Fg-X0V6roDC__8b1s3ouKKT7nnr6MzLh_4jZOtA6f1PSUTkt7jjRjJvYjct0Lp_nA3ynKj8BEXmIWRzuy_ib_fq6WnZLK_gXKzYsQLN8EGKyWTqwQbgB-qQExT5hTjknOhbu9vO0rfyCEcfBKMG2QRtfLiBHDfxAH-Z8a5zgRJ9esoeWqhxK6GLbWnkXWiUvX8q7CUr_aSOaPLrMLdAF8uoLLEKgIWLDERa-OLyaslQTTpd3ocb5UG_37l8OXEzGC7a-moNJb-uWsAcyBMbof45uFwOtuAILqHd00KUYu8A07lQY7Yop78tQNRiddS_ndLEfbF7102eFkIBaUl2IZhG1Kv__9A5KUfSoQIVhNsIKNb8T3eYbvGjlMmweG0itfMFPZmnVwzN3uAnQtxpDr1tQLJIbA6k4z0OwU-ONPWt4ZzZWiBEnQxDLWSYz4H-baZ20aXHV36lM22WhY2xTFKWLpC6fRO-PfUyXyxS888TYBBdgppe5b4bhV2UVXMb2hNsl9WT5-ktwCGW4-vB0z1lXVer1d-cUZcnUrVLNnDk_6d72N_xY5aRxrt3FxhpZh0nTtadZh4SfInJ-Qhd6_5SKmDlamXvzJwG9j7ySQrun9qyKsylOSCaQl4_9Ij6t1VLhBP_tbxIoL8zWXNVkUId6vTMEBjmT14yFktiJ0riODBxBxehXePUNsRvpvGy_-ks1xdG04XSXJANCF-K6hmeFx0obdsyel59_J1yO2RCB0iTSFcMAQUzQC2Qi-ghb0JmeJJaHu2Z8DDlXOnOtULp3nJJhUDL6rue1X2oD7wIbeRTlEVfOeBeT5e9LdnqQX8Um7M0Ypob7CHe1B0TvfV3fH2zIzWqFpwbRzeSrvUmcTlp1lTdTvNiEPO2gq7ltg5YFNyUICrqQCeQnl5PVIsLAL7uNCMvR8JqKZt_SZPCQc8-x4X_ytffUYQE5zqDDCf0UcWjOlBCpc2UBRcnGyiOq_RufrGYbWixxb1tUfVtEBP2rB-vvycZLHa6ukRkvifhSrCBPvdTu0QAAabxREP_kz4V1Xy7NvEVPIlxWvJXQvmWYHizT0GcVtmNqZjdPCloP4lkU3OYWmm17QynUg7C90zIN9hib-wX_rOf1g9IUWiIgRLgLRezheafDaWqoVT5rCskZBqVWeE6dwZcGFYl_wrFvGeYGYbpazzwYX20dyk4oZmQCqAHJ1PhgXaeyFbzsz0jDXdHfU4eH-7-lIRyD8Q8DeUlg6xvHWmR5mnoq9LUFo8pnVSEWgC0QdVcdPoQh3higmTb5p7z9Mu9CMPVZmGE2Nsjs2MphJ3E3kMNqnhaOpCfUhA9zQitbc9NL-p3wwdj8s8vJljj1YPNxfQr9k2UQwCb_XkuA4mpTGnE0hliofKaunBwrg1P0OGM5edTabh-Q2tMMg1tkBa9hEPWK-bFo7nSzI23SDsS7C0N8d5_nAU6CnPlXj-NplICAXXIw0bzsGgOYUaqsVU3SmmwhQzXRpvdrV6WFTCuXtOI2473138qDooVRW9cmY3oxNHXYTojZxAqEQS0AriDXoah5EZ_LbFN7LwiS1HwVcQsHNSVDgFca6mzEsiQHlnakpS706VW9moEN5KQ5lXKR1wsuAY13ZrrZAr9ThNc0l_t3a4aWANgIEHHxz0T_LUpeITJtIcnjAeGvuQ5Gt2FKRNwX1570v0rw4H8lTbR-Ve8hea2OURGDBJ0tvF85F9514xDUPqdweBeFWBCZQMPmsFv-ZZ9Jy7rE_LBnN106s3yACeHZenNFfUSCa-Cn_AwPeClC2JTWeOqf-S4SyTOeNByEXe4EOEPTuauXNdU_EeGlJiqaEcKQQtGDHZfA0ZvMpLzxAZhGFJyhetpPvAG4OV_ILhNOJwnmCmPcu-OrFUfxXfwiD6UPSxwzXCdfkeEy6nOflTzX2IvsrsX06W9ngdulmw5aSyP-eBhXhnhqXAfCtCQKOUL9YQOPrkDZ38kzM6Spg2eEYDAoqSeDLcE7_bYgPUoWlHaeEs_6n3RM7wJ_7xtzvQ7U2N5IF-qvuW_YAxUNPMGS-ETW915nX-vw8g3rVITz4o9pxWwZceOF-8EKtT0NensqWEXrtQ07NmAHkYlrVL_2-Zpfk80S32TRqDy1cAVso11sdrJOCWMwHC97phzmMyoFXKuslb5c7HEgfa6MSyUrUascH9Asn1q7QHCF9_T8Kxrql4SmcDAzDD7u7yEAnFhM2DY1Cy0GzQgBE9xw45IefPSs48VYJXxVZbSk4ZrGGWOTZCYh81nLnETOL2eftIzLLb0hHb60uhvRzfGrS5AQwRhPtRTBFoWmGXi18Jy34EglCT4HsVYo_KW_voWDKfJHFC9QBjigry4oVKogIF-RUG2CguNVksMSzHNRxPYiWt9r-NxAEveGt82tO3EOp7-Dn0il1ynqxuDsr79qJEXpQ64akZI9RbpkirhNI6usb-VBfpRWzeWNok2zeFSFtp9UwnqSLIhBAXllt2f5WI6TbbHfuX20l55NPIcj-0RSzRfWDWSLa4FmOECShjmeWW2XT-NoKH2xJ0giIKSa5Zwdetfa19fANRFqI85c9egDoq4Lew6urTyfZg7B-UF4cA4zrPy4kOx5vtJ-k7w-g8UgYbQhtWc-dFUGszV2OaLpUTZaz6prNfXAxZhdHoCZ-O7gufJaOrAezI2GqvqlgshfrYd_06Tf5CTt6jLUJ4R6Q2zD_s7u7ZezD-QQc2hMt2e1iu7YhNTkquN5_pZokpPfDR7XF4Elkp7RBzxnbe5LQ_4jFQZJTOrEJtIr7de7aj0g5CAh7mArKVUZJZbKaLDBrRI2qpCsQrE5Rz8-lDsDA_H2S3l-G2WV-QIFgdLik-FnU2dttYAqtpFG40bCmoGdXvNH2cG9S2EzRYZj9tpUk-0LHyjyPoSVcmsIWUfwZzgORTRmNPVt0XBPx9S6LBVyNF-Be3XtySmzMabOj2dwEV1Quy9UhPlakoqWRTPgQUpjErClvGTJ7paWLkER5W5nstPxeXM93OX7r7XA==`

* :robot::
  > You’re right: the painting is valuable treasure, while the leaflet is just flavor text. I dropped the leaflet to make room, and it vanished. Unfortunately, the painting isn’t showing up in either the Gallery or the Troll Room now—it may have been stolen by the roaming thief. The axe is safe with us, at least.

* :raising_hand::
  > Was that leaflet we saw East of Chasm the same leaflet? I wonder if it was subsequently dropped.

* :thought_balloon::**Taking the leaflet**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf51e6ebf081918093865744d960bc,gAAAAABq31HpCxHaDSZhPdcZ1zYJLQ8OTeJ8cLOlAnMFdi7Pui9rxSzuvWRpO10bI4HrYOlwHXtH3jwQcwtmKGg_QUkzHLPhi8InVvS-vjPjOy9d3I4uoGXiPmu9IGo_aDy1ulL6BbdJAYeLt6SOocHQuWdkLJiO5LY8U9HEgP0DKFz7g8-qJDGpyDpllTiJ-QWBKNXhSGiJ_6IypI-Svz6MKilu43rjwzDpa-bu53apvcR3dd3qwriWvs_b6MFBdfXOvEp78LH8N9CxeC49RC5rcZ7Y59i7VjnyHPtQQG783ry4aEE6Xnl2vIfUGBR46DQwvRpN0qHntfv5aS0H4dEGLJn9us3Qa7lXREAPNXyAVBur-YhAgft5Na04zmqYh2kiWjse40ZSLPQ4o8WdndoguYTV6pkPXr6TrbVuL1VosmUcAoSD_0VBQXJ5CTEQwjl09d1fY67PSt4UY3NWwqfRffFnEPoKlSsE1jipSMLYSoEYU5g-7HEosez-3I7fQ51u77KN6ibuWAOvXDk-GDz6hm3uXITDBXaPXgFTZqokIodKTcD6Vrp_y8KQlK8iLs5u2q8915hZ4Xz9g23W5f4cfJevP46oFeGybISgpIt2wQoG719RAnJpzYB0DZOAPduXeBHifaHogHba_kpRvX10hwFkzp_yNuGhI6Q2v2DptuqiJ-5DAUElXT7tkCdMbG7ayVLh5yCVrIyAvFg-JqHiDvA3AU5HbBICps6wlC2ZwbGuloZ5oPY_-VZCeLcEFxlbor4KqAtKH8M3WJAgtO_8Ebkiw05h8u9tZAg9_FHdj_4lppabQZSDCPCGD632x1UtMRIs2v_xEuJJZGvZKSbkvfN6a35JbvskG2xyG0wBSgqXS6N1ENUWpHGv3C-adV3MFTK-Wz7CD9paBZzWAGJyuDi6Ur2c14tnQTp3Uu7-FWNCTALyD1YKno_bODs8ug9FjWEOUTRZGLe0ivEhXoiRn9RRtC1TlAS7uTOgcKUCetqqZxo2VbFkWyk4rbXRDSh66U2MsB1YK9dw97akp2ubyBu0n0yGUDxnM4PGFQgwm0TXvk4WzclQnpvkYexe_XmuX0JI6Q7rSh-g-VvJjCcF2eFn_foLvV09EYtF5i_wRXf36Ox0xaNpRAQE0ZcAH6tRZb1UCXI1s-mvQnfraNSPs1jd9FVVQjqkin_qW2Mp-33ySkRAWUEL3bl8KtFkUpBxxMHmm9r4C_jQ1w3jLDivA1mRv8dDb8_DZk2SZqd8T1lTWPxsIMccvfx-9Oof-QKcYQl0Ln8-YoZHsdRHa9DjPGCoTWJCD6cVzj2AySq-lbmaC1VqK1OBHqbgXRrFl2Vk1BcDCo-0vb-T0IXD4j3qu87Gxhu7UYBKPVz9oayQnI_JILq2UIC5CQJ9mkdM8oGvkQKNY2WO9mNNmoVU7VeQx-W-4rXpnr876i_Y8vO63UmyTWSbf6dtX5gTBKsy99eqbOocGECjIfcu2KWnwiT5WkJN_zZ5dvPhB32REZv4YD3elh1_YW7KLRvdKCYLqiHUYy7EDj-FcBEFJZJKj4tddwS-FFzIu5-NajIEjPhm9bYAxZWfTXaaWXM1F2QWkDt6ybldUgk3lqlPYEJBLnoi1yVDEaK5Mn0JeZm0ONm9QFPlGWjySYdKRJQx8QaRC1BV6bOdpFCYVBlw0miTXEpV2xXJQt8Kh5ISJAkgBh4S1vxJlBIKBGaIFd5fG6CqrNCo-LOV14LAHSeQfEjB0lGXnXGERbwiiCb8YxJKl1fOUewTwVUo-fksZP5P9qqVWJnaTGWEF30fWac00mkjO474KK-mMSISZLm2SHEbDmSVGGjPGXjj08zABwpaepgEQZjdtBhUMkTMkritAxWl1aLR2iX__HYyySD0G6oEIOEhQJla-A5ht0Wp2yJFpHhQHbgcJXjxC3da4GfyPA_Nz9ROHU0F0hBap6qqMITQsPYkhcMHsi2hnmaS-7hUU3ZjCRsnaxSKl4ywpa8QaVcJlMMfrrRj81BIsZZaUbrMN8iKYVWzW-PjwvTTyW-a-YwT7-eam0Q5FYAxA2tenSESSlWJhIif49NCLXMqhHU-G5KKvRFWOsKNfUZOYjTJ6C2HJ0Arb72X5VC2zUAms3esQ-E8_7Nu1M_mUly-ikJLJURqCUcrlUtVH2Di4WGD4zsdES3te3Blas5yNKo_YZXrZSoq1C9bjz8JKgI8RPsb_AUNp8yPnpPoejPUl0DUuQ5mnmK41u1vsA_kOW5iP9FLDclTfhBE-cSmnT61KpVWeLqs_tRNR9ilRatkIBb3pS7JPM6y9wKtnfVKCs7UbO9JVEp4Kro6TgFzIRGFlEAu6rOJ7lSil7eki8YISZJDR2p5_rnkF9dFjrwhv4LNWycM7sawGOwvLiz4mM4KVd9nmmmVEMggkROZEmuHePsZw04IFlnEX6bh36hIr40VMi2PwkmUQQ-2m2MTILAbQ8lAjgr1vNQW1MKnp9UUzSquC-2E2h79ptfKorPY_7UY4ATvVl0NQr4_8yo-gHMET3aeo7tTwlfUaR6eL12-lSEOI0bJGHpau9TuMjODfcUdnzrAgyBYmKN-3I0LhQfWyTQz8hBhTNTUkwX7VERDScVijP6xu_JyR4LYh-j0gJ_hcvn3ddHDCUAFPZm0VfzYbIOsh9z78sA4aOxV2Vw6YLhWupLlZxDH11w6NHliFaIfCexyTDngSUxSRyvFDs0cFuafAYaKwtU6mY1mkYm-0VRquqO66HrSybUV5GU5oHPbGlIVhCiJnTUglzL4AwGLm6BdZ3jXdUcl0BAcL1XirtnxSdGRL2TpsuLCnqB8V9XtOIV8TG6zNbFq46BX7_4KXqYsEhyV7skbBdfdD7vtTjFyjyz9zETY1LZjbWDM8fMHhDk3dgA_aMbSAfEnWa5uvh1kAhl3LfbYe9qQ8XrqFfgreAdVQ_HSvEMjiLaQCx6KR3XivY2hk20asHD9cxs4WmeqMsqB1NMW1yhwSsw9Vy1rhUvLAtBFEp8Jc909SIT-0HSU3s1ysAUmTTYtcQ==`

* :calling::zork,call_4f3e9676d171433f93c7a7662a2da2c6
  > * command `"west"`

* :scroll::call_4f3e9676d171433f93c7a7662a2da2c6
  >      East of Chasm                                              Score: 39  Moves: 49
  >     East of Chasm
  >     A small leaflet is on the ground.
  >
  >     >

* :green_circle::call_4f3e9676d171433f93c7a7662a2da2c6

* :thought_balloon::**Taking the leaflet**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf51ecf3c08191bac8bf1a4095f888,gAAAAABq31Hud-Igb_ln3R9ofR9ZSek24uUeW0CuxlSAcgGPYY0SlIMFJDVBC-aG50BJWZuFn_ebVRdsDJRDZahUv25itlPU6xGDd6HRPb9VZjdp6uFf5zz2jUzh1x3Cy5Q30KFnQjs9SryycFwddhZNnSuJzzjCS9MNM5w0OVt7lxBkPd9BOJFDJyyjqK1CC16qa_E6irCtGqQ1eK2LuhfvUmrWxF3BRfS2ppeL7IgMl2oAXsoubXz2VM01Ck-BdFvH8DpHLpEFBs5N8bzBb3xqSUApN3P7bu713S2fnVVQHffTOLrZ2M4eAMRRCjCRURzTNijOzV6dHzRnU6eIjNVWPftQwfnminUVIykZaz4wQpzYa2_DjEdlJb50dYvJo2S0qoSwl5k3hfa8seggBWFgd1jCPcocksON_X8IUfmfmyuPQ8KlZGdY4IzGLF9bfhPECzja95140hqwiAezTW7fYZeWxKDJ-1l6yeWdVfTDX4Y8wnrOSe4Hk8cFikZIlpmpan_bhYXKIPXQjOlAu19hs5fEonXxtxQogc-c9v_ILYprWXs6Ol5W1Lvyjdz4EFTRjPO88HDitDz4K9iieeJfsYjyi4GYoJpn6Dow6QqzYrVdeXhd1hzqy5vF3tXOla36otehJn69jfQQTNs4i3EEolfaiwshNpmwmwOIf9HdDCKqQcqUorqzL4MvAweOKE1zW9A2IJEHNTo2BOP7w3Voc7jSpRTQ9fsS5Vupk9aVm7pBh8iQhPJ86hmmACubQDWpucgBGaJOlo7VxFfw3DDvb30iVuJ412nTdK-PmNGxU67WmJICKwZaXrmUXkCLi0zupMv_GpnaXhQ1QvVEoz4Jsh67kWbzgGhNLJhtsQb11uos__2fUWzD5E_D6mMhBv6MH873OKw47xO1emeTJPbzo7segc3A9qwmeU8kYfIn4FyaxMA4nb7oxuNkG6L8XYE2FfSbTHAUF1jR4EHBPje3pTm2qvwgmA27FCCuxrm2zRy_izZOnWKpBIAbwI8a7sGn7eUGUzI3qN0F2E_Pf_GQLg3KeZ1tBcVZwzS34yTwSpm7zbnN7PG-mb0keufEzGUhQD7PoQo1u68xPn8iaklrkORyUbRAGJiWrunafGR1BSNFr0ZMYNcBsemha42_DTdNBVfEWch6pVg4zfCurBGKaEFgKjtsHWTsVx80TdwtOVyiJ8XqriR8A1ppm2cpZ0O93YArFJ8s_l4_q8cAoQlZ6okaeMEo7zPKtyUxe2EhVMKpa9Q9gTYjn0xmJhkmsN_GFwZj91aGf20RfqBa7mWLwGriprVtBolQYWOxJiqlrVi0k0a2WWMuEHDhDQEmktwo8IzUrq2irvYvYt4k5wAwfMqjgpWyFPugL3nd6j4V_0U4e5N3H33jheIr8C_g1T2yBH8f7jUA8g6bzmE29JZJk9u56R8BWRyfJXiS9MAo_4e1_qPd1g-F-eBFHtbLeA4M7odnKYTR8RK4zeRoPG0X7FGGRYiVmlNfbhM72PRMEBQ4-u4CLzR7Hm5YVSTiRtTLfvGanvyJnRynletszOAsjyr60CLdPLR3AB6BFcLNNz_7iwENG8ZUlF_5zEUF35aYRaAZfHdVQ3PgmBZ8JSO-O2A1pm-_kpXl8qIWa4OPa1QM5He9xyE=`

* :calling::zork,call_066aa71257964976b90fd7e757287ca5
  > * command `"take leaflet"`

* :scroll::call_066aa71257964976b90fd7e757287ca5
  >      East of Chasm                                              Score: 39  Moves: 50
  >     Taken.
  >
  >     >

* :green_circle::call_066aa71257964976b90fd7e757287ca5

* :thought_balloon::**Tracking the leaflet**

* :thought_balloon::**Recovered the leaflet**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf51f143e88191a9f44484ddaf515f,gAAAAABq31H1ddxY768Zt4apJO2xN146tv5oQk3isfy6yPnkR014bqNdzS0GkHqEKf-gyRJ7LAlmMzhCQVA-b0_L-Xj4W6oxmHQu1HsZ9Img1NsE_xHtZX7VI1WFzqW13DeLzs8CZizz80GCh6oOg4uqrCi1KWNVBbUPFCOEAUe9thItkwB-2LM3PxJhRNAQsIJZdTyCEdqMx_XCv4G9DXDg9b456lAlUT0_WhLOQ7_XL5EFIXHVNpCuWu6VeeaZ_qp3kjVqb_Ku_KTzGbDF2-zwq2jO2MXztofN4Oh8v-l8cxtV8qKd9zrqz33xQivtgzghE8iX1DWoKvyoaqkKyj7z7wl0tVb4cvcrnXqlbKfT7VAHZHIj1DKOyUh0sNrv6_VNc59tDngtFSA5Qs9g6h-rdh6Lr6u4ehixl7IaCG8TzQ28ZEoHnu_FX2zOxZ8-qqrgNBPg1hg-sTgCwz6eyDV9LoSNiK4xLt0-DLLs79747BmLBULfFkyWgtHtTqgO6KCj6u8n-ofutFFKM1quWUvzWNATELrh7v6S8Sw_4jP5rf-ulj_iqVSWh4gyjbQOyZeZzJp6pzQv3visnyBjJgq0zNNkKGGbHxMXdUx1jSA3fDBNwruPsTa0_wQPCPbNbopLtjgPuZcQC5unlF0yoQSNvWBrVQ1XW2I1vrYEdkj1HRwQBY8he_2BR_nSRCVieUWRn_71C3KXJ6jqJt5b8A8YFhs6g4Yms6J1s8i5UC0IsKZIn0a9xGr4wCNEEHbpDfpehL86CWHVPGc2EqHkh1NACVJrygGG1VwukuvHXiEd6gaOg9EPQzNhNeSBNY6dXVxH-wXYzcKTV5iO1t6-poIgletmqul2tIPiyEx8Iy0bo3Ik8ct_l7UJjN3ppYBtYzubKd62ONjKuyrV8PC0EfRLCWFKQ6HToJ3RmiU6gYA2EISykWAnJTIAN2qHpuXl8bdyoIyxK7qd3Z1HeKHK5sHJVSxICBuBrN1ImcIXn2i-3mB27rx6r7-RGOf6mhIdGtTicjMJAK0HGfKcpvZQUKbLT1hO28bwjNJCJaOC8enZcznL1IttUr4Jlt3K3s1-WtUkoiS_xO-pMoYNWscf2m6CzJ5a3bXKFlW17ppdMPjkH3p2E_xIllCeEeCeWul7DMYisyeiNejezcllBUM5xrnTLRI-ZfGJwVKA17b-qK7Y2g6yQmf4XkzjN5_PhcDeGQmg2tpQC8On6eeY9YU3ept-1yTQ02ttyZuTxktjsNw-AE6TcvG4rIRgyrmvENHzsm6x0a9561ma_BKieBhHBJ48nl5W0n8302w-t9spFwMqW3OhbfLsBDBo34Rz9yBrbbaQJWoeIi7Dli5oIk6UxL7D2q5qFK1eyKQqX56wA28qATxPcbNkK6-p4auUhSONCOlgvWs7AGLv8DwoM0n3gWv46pJlEJImQVZOqEvED3gCfSgl4FaVg93v8qyXJCis8ec249UVXhmTFJY5lm6WwVXL0LuKWNI4xaWpq6DMp7TQ-jneBOCnuA6fvxSwYUPxIwayzTUqWqD7vg2LHiDpcV0DSPQTkw_2YK7JSsf4X5LPUErGBnv7wjSSx_UUhBGMz7vk3MeEK4ne0N2Xl5KNV2_dS1HAPl33rfSoHbDTcxguVToNy-nIXNQlisMrU2CJOSPj5m0me_BNq7HGM8IisU5a8Z_-mstK6GSpwtu0GAC9sSz3Pm5BSFAKrct8Rzqs09_bXFKSoqx3a6s84tII7aaLSjm4NXTLkLfx5iRVhfJspw60EzZJ4VQh3inSXai9qL7jtb6W0KZT5iBPt3DFFHslICe6YtWUo09MahxYgBNTIUHvk8-SqnCWiSi8FtVn4nvvKYZbpOetxv66nlPQz03ivs1rjskIN6yR4pnQI2TbxjcNH1W26-A6KHRutVuwMHwtY7hddD6DB0r8JxznN2Z8oBak0SGEBNwnrTOinhvEuagpBhmdOfnWhAkN6LUr4P870TOAvYRdF3OGR9oq3SYgaF_DSrgowsY2CYVnCRO0qFTyKJoBSHcJDI-GzMp3hNvnsL59Bv-mQon0Ep3v7eUFed4K2xXGrZFe6kKNS4mbCsM7HL-NJGReM2T46tKq-4CvdEkNhdKVgAadD03Z6jEqkdPQvPl3OET-5tRG2iq8IE7wHbVVBYfCBjILkWV-RbXMxlktcDR0X5Wp38vrr1rhaawc57uXZhTjbzgBWZ9W-l_mCP4ozLFPw1AnP-HukNSv4sjF8iBjeKx2-x2nIEpEx3Kk7zbMAoGOZDOOPlk0TcaThj0qxAYAwhk0mHIeiVchhA_buSIipNx5fOuGnvwqKVnf6ZxxaxE_BQN3ltqM63YbHXxdkjGndH9ALGHbkRJl3pxKt_DIqmAywI-5ucjRduauFIYbhKIqBLlYmkHIDFJn8uWHTz1B_bs2M7f2Z9ar8FdqNFBX24DJAw4OTKhjn_HsQb9Mb-CxyauxBOLLM16nm4k3YsnfBL5BOxkq6lViQC8XSQuPCC6Pz8XEz3UGqUEZCKpP8S8y7FkRYdT-qxnZ4LF4Qso3bD47mw56O5fRa5c_vA4M-uMZxMJ-syz-4pZj4gJjqvljuACqKHtjiB-oF5wMSBeGbMFxcUhxRBASu1j270HKrjH-r4-dOfTP44U859DfQoIsPRmRz2l_KiwfTUm0GC8NBWVyc7dSv7UmtAWe2WcQzMjYOZcEkz5IJVSl7RhOz1w0DJW29rfJGfJM2-fGu5F2VDYbnAamRk1utcx72Whsduqr8sDOi0fSrqd3duAe95z3dbdFgW8muwfafb39hcxFPPuk-2qfIFuEHAxXtes5-7vmmEklsgk_6WvF2a1P4dq_kCpsAyvth6LYgqY0WbZtMrW8nXdE4bJgPwWoqOJwFTAGFImjSxVp_j-pyXyWIlcHCAOtr5xtZW6ZSwTNRS-GSB6wSOSPl-X5FPKJuF93GilXSMowggVfbekQEcAyt7Z69g6EpU7b4oVozR8FZFXzKOH7X2uKm2syK2UpufHCJoB0Aa5C5IZHGKBiaGyf7iMyVmzAQwpMtPSAaLReCW2QPhfmFtRpeb4WDHf-Slb1dV_jfGJPGA1ZRVogdi9o1WzNt1fhNVbzgsvoY5N8--BAV0b3y66aV3zdKOMrzs6wPkZWCOIGrD7tsxeXEZsJ5mS556oDI9lm5zYub-fFaq3drEcUX60NuVZtvOxPExMsKkjEGN7-RPHLqjxx8JMYPDuZd6GF4pMODMoASw-dvWq8yLDRrnDdtt96SE4otCcs--6ysDLfkp2Kfg4hRvdztO8DQcEyxWlAZ5joAar_sYKus5DPqQoxdZuLXQprG-J01cJtECNQpS31woe_WuXv2A==`

* :robot::
  > Yes—almost certainly the same leaflet. After we dropped it, the game said it vanished, but it was lying on the ground at East of Chasm on our next visit. I’ve picked it back up.

* :raising_hand::
  > Read it to see if it's the same one. I'm wondering about that thief - when did we see that?

* :thought_balloon::**Reading the leaflet**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf521a2694819186d965afe5966019,gAAAAABq31Ibv2dKzr_pYv4I6liZdm6GZRmK1LRqRQjfyYKAQs3gksYL0V6J3kXeCPDWmbhBZHhJirl2zsPx55GLXGmF61RTSH-5sZUIe8UEGs9Sp7ExfBgUt90ToUgZNEWFeJD0qMmua1OTS9a2BE9a84qBIodjo_NJe4oVkW7C7THzPuNFdzih7WzDhVR0UM-gOj8UaKuWZORO36RMGiPHn06Ka7GRgQm4vRm7o8yRD8ZF12oDJXyeH20OKjNDVL0ASK2Rxm4e1ofm6ao4ulYQqQ2-HoV7PrxhAT8EnEGkNbQbGTr4tVdNZmkGiFirkjaldIhxtm9lsM4putwkKBGdaKV_y5_IznHLyizftMpD8TDJJvVG4wtBL1TPzndmtxk0AdIV_H-vLX3unZxKuS94DRqy1AqltduifJuij5VTSaKvjzNHX7nRcguYwtHl6ZDT1W5Vl_AUL92pl8OOQBOkG3vO4jRiDt5WZtM1i2DhkoNIn0DDsZHHrLNsEy3aWTw6w4zaKt6wB0XZo9OhyPro-c__tAogg1n6SO-JPDvMlqlFuA5LfRWLGJLCqzqVLG5aZCUHnuYvTj1jGIPgvXwuqihT-EwteikkLoDt6lowIme73P3n4dntQ_ZZhzMrs2IetchL0fG0caz6PmkrM68ag6Jnd9smdXKqaq2uVAGXqR2XQE_JYzpRYLBdB1Q96VWmldJcRCw7CTaeXeo4BT8VX2Ajv2Uz6ULf0i39iwzeBR_17xOvzi8N-vperWsImrJRQ1W3AhcFcpt-nXdKNxI7LPEtB2QWT1-9mO6oFeAHXZX6cisUshF84JrdkAPMa-Fq_YVuu4XUCoAHGPiSNOeUOvk7iS074C6RY8PVNh4QBrEulQw6sLcxe50gksvcH6TEvRf67qVaq8OhP0Kyg1Hp-qJoVAjF8BJVpfwIDjm7Vgdel_Yt3kKPJkIxCuIVlNGRpgYfu7MA48y9zyYFpdRL6GuwnyoRWR0tee1_awROCrUMbyKPL9v5Soe2ZL9DaUGqc25iF2YWWRsWTxwDKe24CRABsgidPwEsbYC-YxLPB7cuXIb2VhD3nYgYVUHavhrWinecw0BnigUUPRFzB8B-weURJgrtVVdPShRHX-7G8DRY3QUpKMJHR_fNpB5ci89dEQHpwuVZwt5HAqARzPOlb8cVGOBKUnLSNHXPHGTKDoOHTI-CWQQFM4-rfbCMC19e4DDbcAcGrV140v9IV71rJjlCWxj8ONcwoMNQ_Ko4zVKXf_rWOKdEN1G_YvSA2uC1EXJhu0_e972tJtoxTh6TJCw57A2DJIEnXOGVG9XiPhjeAKdYJuQunrY2K9_em3vmwPIdYdHnKBj1PEZ9sFb6PuSDmv71YZBN3PE6xPg3B454B0Y-kuUeaTtU_k_x_Cx-N_c6knXVSQ-OEE4bvdiaAMvG8zRUmKffTIhnn7DTRzLYgFPz2bYHuN61pYp7cY0mXSqTUuDstMktpX_HKTTKtaGd0lrYYMz0GfHaEEgrvrCkoXwoJ5LeCVndIqEeqa-E5P9cJrMkr8edZvSc6Q3UG8SfmbhmY4CZpq4G0lU6ebsnkONr3trJFOnf7P_CRNRj-YrulqZxrEBX_lEI1HeyXpLXxqGCnDysazekgGmOw5TMXUnu-jJN3F0rmK5L_RdJhwIETHiF3B0QF-yc0ffN3RGqKlZouS4W5FQsmcKV_nP9uSb4uvzyc-JEnXIoRWTckFf7TpIpeG5uvv59zGdQicxtUo3SJJDU55oZS7KTSEypILrEahE=`

* :calling::zork,call_b63af0523d97478c8b941319956b2fa8
  > * command `"read leaflet"`

* :scroll::call_b63af0523d97478c8b941319956b2fa8
  >      East of Chasm                                              Score: 39  Moves: 51
  >     "WELCOME TO ZORK!
  >
  >     ZORK is a game of adventure, danger, and low cunning. In it you will explore
  >     some of the most amazing territory ever seen by mortals. No computer should be
  >     without one!"
  >
  >     >

* :green_circle::call_b63af0523d97478c8b941319956b2fa8

* :thought_balloon::**Reviewing painting’s disappearance**

* :thought_balloon::**Checking leaflet contents**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf521e381c81918589f7e52135b072,gAAAAABq31IlVpTXZo5YSreqHJrchNQ2zheWw3cujximAIxRYLUBgfWOcJsZ9No1z3W_2VXpbqvInlspxlk80gvvnA4sR6UjaZ9pgMNl93wMDYvK4ZfMt5xCja-CsowSOZbZhNPt0bFTronkz-Dt2spSTiBTi8GIZQzCNuQG3Qh4bOzf48tIBv8q1dbqeFBTAB44Rm6a7utwM_KgME6ZxYlJPZsYh_ANL9ylFFOVMxB5uRDwGLOzwPiXZzaTYivemm1ZOuj4-1gxU1R_AfScFK2XHy27QmB0Ax6S4YayjrwNCc0liu5vUpXWiktOFnan_SIqPH-AQv6FIyNSqPZ6Z1awkUPVQ9OG6KwJ-dT0ya8A9ssUP5Bl1sEY9xb2tFJIGSPfsNzGQjfUuvXrNRBQcwbJ8aRNGRxW6oldMQoJgrbcoHNGjTLc2vggeJ7-FFxhOS4604URKm_MMI2oYHyBeN5PbM1tXN1AuNn9GI6R9N_59ugjADwnj9RlnRryVK5aJFtLX0cCht4MG-8cYajBHz7xDvyYXi3y9SMFPmRMh0Y3UVWQ8Y6OP0yapA2bUVzqa17gG77kqvhQKLSLy69k8QZL9Ut0tYNbuMajDHuLTVlNfbxcMENPLPBb3JkextEzTpiffj-AHnfzt4mLjm-DCNLUBdwh6_3dh5KmF6lOue7DnCe-h3iXaUffnKx0GmTaTzXGvdeJvrWHDrr5-IOnu8EP28UwSKA8O5CqkTpDkmzeYeVIzetW_cTrZI4xiSS4JE7Za6E6PjKsx720xKLDAiuR8Oq2zKSd4ly9AFurYvkRD11XaCMDhuqb4VbQ6f--qUX80A_XdTUYdIJplClRa6DMu6GYRS_flQqOAn0Fkqbx2sJQNEmmNNscxuzUHlzXmmGwB4eX8EXFt6UW3jSHAlok05lVrWx7NCJ0ohZyVhgWNM4NqJR47lbikE0hJxJDbiK0KnHwyW_tjjznUW_FBk9X8A_9XCqAwTBoXfSWlfuhYpJ0Lmig8vMDGnZskyvCtoYG-m6kcHbMACEo0SIvlcTpKvrBlsaamAbE341gzfEwaHuVpzSplg9Acx5anZC2JLrnzPLwcIU0vdO5RbXoWvmVer-9-Zu0wP-8FFWfNaivyV_igvzuKbSGgeLU_VFuhJfq44GEQYRV12zTx7tpqEu1B4C7rTT2tMNI7HWzcRgDGlAw73pvtPO9m9ccR6t-JIdz8vJHV_ofyOD7c6teKloqrYNb6CxpKRZR7cCxWWD5W68_dBCU3RYx0-du6TIYyHLFwIZRB0pYL2cUaSds1Epmsz77q6tCQjGSV2S0__simuE40Khi1Cz2MpvUyNtVLpk93OGLcCaTj0rsGDe2HN8-FEZCjM8gUG-IMvw9CKdgUKORWm1l_WqEq-yNY0coZLZLpF75PHsA99UHMkM7erioSF8h7JDAbBE8FQ_mEawojYpu4jJhEWyo7RDOL1rHykSlxMWHpn0SzytjSmyK9xFX9MWQVl3Qkq4PMzfnhxNcFo1tlDjbZXzJGnILA92JPnTmvZ6WEqeB8OCAhTzq-ZH8BVdqNzxY4W1h3PAQPpRf9UQ2QfETgtUauAa3RYsBcJiJyfzpFVpk7hK8_aLmIMICeu2X1AUV88KfATc50epmW2v9NGis24P28aUEyaSQfsFElJeuqc8Lse_PW89XwXcyGAJlY5MeyzZmLgLlv84JkVsOvRlxWtJRJD4mKd6M3kH2LVOtzL0UMI7JVKtsnU_DYNqP_rL_ySGrl535j-Z2QO26HJjA7DBb0OHWlrg51NSlkJrZVWIxDZ1vSEO-WUZmiOrmasCsfcJ-DqYa5k65ObJp55kXAxmY9YsU-kASO8LttOmS3190A0FcaNUyWCCds4wvtQ79FAfdGHiX5yNmYdXN6SnggSFeKfh68PBUqyN-U1zP1coLGP4G2rWgkSSGqH90rUuzd1sO7EjeAajd5lQNkLIllOoFAu-NsRKIHldy6aXmSq-fRzIOzktqfx9OVci4ppiV-SM9vEJ0ZoXQsS9m-d7szKcYkndDwxbJ1kWjF1FT_1ntPFTGOzOpxckF6vwWj4PBEsxczVSmqSfg1Ta5H-aRjZ0R4f4RZrRpUSLhwQ4pJEIMoyV3Mi5iMynVqdWnlaEgfTXMXixsCFswhTjcuWIEH4Gg_JSyEV7sJKuJOD_8GPrMlQSKmc4m91J8jHZHCUB9-o3WAznIy4JMEcBFqp-m8HHBB53FjX5OEdD1NVbJlIJNdi23iZZCpx8hhEc62vPVgOxAJ2QrwPM2b_Fy2gfsRO5vbiHsIti7pqQah6d5WFuSfJX7tXBco0dxYB5a5Qxvge_P6vkVJcf1CYXBT4pmRE9s7PPs9H18vM1J5RcsD17dbZl0Y_tF16lmBHJxvud4b61YOh6eb3UThvBFssCE5YssDcY369PwQjlhM_-OtKEgxIUHaVHcHiEjNX2_luWEqgEaztuIqD4KUrW3l71fq_GOWRi0svKojesLBgr9yAw7nKLb3HECw5X57IXzcOD-diEDHQi9g9L5x61ojVd5bJmtf8GZliFK1nW63ds1-fWwI-2S8KjNav32tPctHHesIoxuNTTlVWTioeP5W86iexdyOOpk99RPhD2F8tiCCMoSswTlgILZvlXqsgT5ej0ePVEdC2WfEYPHkUyZHzFbi511X9zfl54z_BZV655ZkntTtdqz9o4B7BPEnSFp6yHIkFEvQ4phzZOu8hCtVHa6P3lmwMtpg_gQXozaFrzHX6jday7S4PsJk00gHsZRQI8YuBz8cl4gQgXVlNVt6U2yc_ny0Lyq3xmUcb_0TWnAYGEEcd1c4Gei1gD0YW8GmJvpmHvWphu5pgaF776n2RlU6Dw3M2uUrAkKixzfxtl9FYxpNkcjgdr-1Wns_zS01iDAq6PnEF9g9hmiDG-0OqxWeWafeih0rEIJz7GW3805NdayGtlSgPK6Qqh6AXbccqCzuj1rIb2ppm6f7pDfDYIac2zgIBBFaPCMJfNAhlwMWeuQzfjnzZnK0xQNoJ5oB_t35z9EkBXS3eAfkP49YoigWk1b77Q8LumJCNOukdkSVJWUAER5Ypb3LgY3mhsGp8Otn85lAP3M108wKRpD_cBjrr1iGsvEGTBs01nCeu4D3qvZ0pDQ5OrbOVAQx_ODLfgAUmaqlL3B983_feb8yPUFXr525CJLT1Z_XBSuhnd2AfHwKWGnVFWe_wDYWhwpgirEwNg0hj6BUUqGlmdjVUhj_sWrfrG7r-y70g3KFvycjEBqofIeBz7hwXVuIBgN7kJNUztGes4lf8NFgiFmxZRB3SySUUkbTw-dau9ZRiTJJTpB`

* :robot::
  > It’s the same leaflet: it has the same “WELCOME TO ZORK!” text.
  >
  > And you’re right to ask: we haven’t actually seen the thief. I was speculating when I suggested it might have taken the painting; I don’t know why the painting disappeared, so that explanation isn’t confirmed.

* :raising_hand::
  > I can't think of a better explaination than a theif - what do you think we should do if we spot them?

* :thought_balloon::**Planning sword attack**

* :thought_balloon::**Framing sword advice**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf525b8f40819191ab20ee5b0dd533,gAAAAABq31Ji9a7H9N0sQiWOgaVa9mqRoQQIj95R0ceQwhwvgXRBssluziqmEhLvxvsoScp8wYf5y3IuHU4yHxs6YvEHtUcq7L15I1c_9XTPDi7AXNCNFQzJkVmhd-XRiO9lJGWQigX8EqK86pc5LQrLPWjBsKBviBlApStpwI_XLWFLt9zpBII2cban9mYTYeCIepObnfZliFit-35FE4BES5cLGh_2P0p-5i7-FzmeLi4TwZPkAohmwps_5h_gfixprd0iZf-GInOMrjqLA5mXc-x7Gg1TRw_Uwxl30rcNF6X4ZJMbZn679SpX5asO40ysPp0eig809jQDU1tFNkmW5DWWoOFL-g-t9NYV8gvVt8f9fYBlZ3juNnvKO63z8DQyIS_AXx9U5iLwq4ckh5j2VHNLnWEx5KFgA73jx1YQF_YxfdKH7PVt8oadAvMmwhoBSJ62gjdPxHzOCZdfsOzNRnAcWrArLkHsYgHXia2P8eApa2Ksq6F0dMgHt9uiutFRhRet_ckPnO1tHQpkPUG3L25JEoRGdq4kdWQ5cdu7_sDjlLFkj8eeD6B50aCuIo_bMuU_WsqqR126SYaAbigV50DhpAhFM12ui5nhawQVWds6UzKKrst0LcZaUNtNyF_mRGbP7ea9Ox8k-mSlvb_PSNZcOZOFhfb5Hpb8RX59_S32AtxTlDROcTHf1D5A1Dk_y_cJU3SD6jO_pFKCcwWkQTZYAr7E5LMND1GZAQYeSxxnsgzxrTzYaEJVx8tu8vIn6-6AzcPBC-YKVWiV1uWW-NWg-tVGkSDFZNzWSsVrj-exoki6fwOqAne6rQiXDfrWzUBQvjewwHiVt951YDbtTpne79zP2pEoKJM02sL_13Sc9XJIYKjK-nOIIZRDbL56tnrEJEPk3-Z0R_lRuiGz4h0cB-gJyor4D90KLpKfZSmdEQaRxjwPvMqcg5cVwpFd5IxVW3Rk3V8reOLjdOa8igAicqQQ6iaiidOslxoJIZCdv59McaZzKBNLw9_MZjoRWvoY3TKlnEI5VRZPyDlXz3RZfX0AIkBkd12JCTzS8M3tlCtE0HqDOHqhDMmd1m4WQKhRsZ-U-wtWP7bU1fWRUrc3IFZvLZrBZrKo6qTlpJq8961pbFVVCaUPT8KjH7Bpt99OJnKc3suhzGtxCBurckAf_wgEej2fEQhVr0TmV08VMo2dsDSqYvT2z9zMXbO4KoEQ60COgJcS6GtfAD_Qwx3SsIUh2CqqVLO4_sv2DPbEjXNkXgZWsgyFLHnZLRz58OCNw2at7okSP037WV3_aFbk4zZ3d6SYkRxlucyzdtNPxQyBcMcG_crkUWxWMEdoKd0vfZYwGA15MejdMP4aVrvfA8lghhKQYYL6Twjn3KEDD3QQZ9E98S7BKyjzacyt-rBChk1SSACKP9lkfFvQlGFIAAqnpCXFQvwfyxj-JTM0hmsboyU2XJfhP-HoaoAW0-5t6_94i2u3S8g89kFJuSK6EcJ80Rotgj1nV0jvyLCsmTbG_rDLQ4YHloPYlLD8sICvtqxp0MkpTYwcHAkZarv8EwU2K1bWDGkjAIZXIjhmW9ITlSA7oTbOQ5eU7hONIdGnikxAHVQRd7o_hv5zezhmT3jDOt4PwYppD7msiKfy3aHfuTxgv3lWpGY_E-MYbdFm3-8e_gcHWwLdk87vW6F3KTwglnFQQDxO09xdHFNINZOHO2v1lpUd-B-5-byut5dImtkvqY4p9MEbyDsvo4d1dNsjgAO-crXerCNyn0wb8fVJcKk0p4Scb21ZZ5eWtx8zfO_J7xYJCSIqYLRls9mWC18gVLuHDSapI_MPKkFDHx9AONPeFfF0aeuHbZ2ceC4XwrD1-7ZVIdC0Ap5F2qpySAvNhTQJDMmNmriBk9DNAKaCGDgG4-IuhHW5j4vq8XGqVN9FygQiusT547emkWu_0dI99VU2pec_k7Gee1EeNHTJ7ukV7EIYafakWWLfXfWgaenCpCL9eDK1iTwgLutvjflw_ZqXERrUPfLSU5ZyIyy6svFCGCZJ61YDf5Nnzj19IN6WZpUxFXO_CzYNnGl6cR7qzaARcYruVuEwhqzeJyow8K-wpFApfx1wvsosLQg56MgO2woLnd9jFtVhdgE-owUMdzwBHQIjkWl0Cou1rgIEaEb1nxEVPHUf3sl-nWLVQeWVTJMA0_NwufU51pmVz6lQBJOPosatGDkyGW9iues--_kga57il9tV8vSV_kmS8VIJrGB7xo_3Hwmld1XAaJKyn-Jt9nh9ptA0iM6XlWZksJwgTVrA9eJiQC7cDsW3Ak8aAX8InMCkTd3mGJgHyWjOK510irZiuAAspJUuF6kn2raFw6EAdWLchfYMrZ5PJm3hT74g9x-jKKWPrky_FaZkz38gd01jfPXbsAVOItZ6foTR3GkAPhxYrZb8zeNQ-oPXBU31hB91ix-GUJ9Up11A-9zAb0hE84p6GWXX4b3tetNvR5UrET-YMyql7LHQYzDQvrqJdyQtM2hXVwBnpBshB2R7ZxUqJnUiaoAfu0fG6ccZR7zdalmEMenO94DjiB65Riu6JbD9YsEou6rDvSp05bUNPHFhwvJfiDvVv8BOUseffCf1F-esJ1IWsG04kxadoNln1mVTnrqy9a-sKFakinO3UzlZEbMZFRjSF3E4OCWo9U5T5RWRMEx1LYbf1SpWAfjikSyHGvzAy4bXIAiQBYs-rtS-nD0rC0Mf2uULoKlR9rdYGKgrEXB-25AqBkIbvtvR89BfDiNVdVHwIjLa6n7GXoDE1KHZU_G1WplYPtG1jUTyLRsK5MKeLNilyXYKsWaDsi1Xn61tin7gYJzXceQJ5Su6vCMBAkiS-U3ENZShrZTPTwP3EWqGt9_Z1GLoo6iCCug3syhc2d6ijgtNTXFEP1wNirax9OxKyul-fq1GsnoNm2DgFzyYrKXjwU25PYUopVFA1zpl6ViOhdEdyENmqPisKnnfjxHbLrhzvmeYmQlsd9kqu3lzVKVqKw7_K1PV0eFjFdyd_Trfc3cQwUQm8-I687BHNADJvecFFizVvaridE90eR7GNvqNzfIOsvBrMA3BzK9le_uidnbaiFyrsneAY3yiGTnmAmuoE7dT8-3OxT774Zm1_lhx90iQ6bJyCSp0kGkI2GPdbd-lNjnC5SvkfPFiEjm1N4vj6boZJvYzBX_P8bCsJEdqq-4M4uL_m3HgjWZSSY3HkKG6p5GdDNjsfP1FiudRlmYeOEeG_f8FPcnlX31lqXcQLHtYQg7ivDZiy65Phc8NVzRxcJdwaC9Y0iF8lmi7O4Yfzm3EBJc0vDZOV1M_ARqTyZU7KaRPaMBfJOV2P7bCOjDGP-Cp6t_UQfffvUoU-Kqp6B9eWh1-O7hs-HMDVU3X2ft7wF9adOV3ER4kTPy_G8y3OM2BQ5Dv3ytQGW1rLqkvx-WAKCmJ6j6MY8cqbv11NH7mHOi7SIyJJOXmi8ghdOlFOCwHBm1iotutBGNWCYR0cwGx7hWVAMF_MNkimBnUEYpvU0iCVzb7-duCNqL0CwsTZTu7CYVc3-Y0BG_AXM9Dbtf-CWcP2z1ai-WN8mKrVynz4WRd4o8Nd9vZWndkvIJ2b6pEZx-oZgfuKtxBnCGeudWwvmEYiFjgQ6IW3SbX2U8bPk-wvCqFJk_sG8j4dCVJl9XVfiVUCMP21WDfypJR-xUYRDzszxLHVAGvtc4jHm-CBAmMJ8TAMRCjhFP2AsZsAd7nwQ5pPLtu2BXuIPOsqeHnGGxePE3sFKOWO3eDAl2niGglxV5EW7ofQB25Cfe4b2LyJUkN8SxcZ40oiJqO2DKIezQolUPf8tptfy8zhTWU3GP7PGxKuvZADuMtM7R8wZy_2ZMKKM3Y1zpnH-SeFnZHHlJPcS2qEJWS8DS57nR_qYdiM9VQ9f8NdDWpO4a2F8Jl7s5jVU7PRnt-KDsWm3IOVycqYUXTgnEwv_5hatc06S3VTMmmKAs7xc9CtFfZxVqo06YXeeIPOJUI-9pY10dYl6AY_plVpRRXmxpu7-BML_lbG8ptLO4sN32F8CnPESKGWVNvG2Kr4e4AQpDx6UYVsrjf0zDajT-6ROODE9WGZpWZ3kbq1_EnEfodVR7RX_PX6B5iW1hO6qbIaF9gbUqvt6TWeqopgEytWM0hRamqkhPHNEeww9L-64bKLe0TEZ0hrY1g5AhI17N6GEnGZVeexOeMok9Ae6KhzQ9VPh9tSQ5jYO1qeWa5EZmJG7z031c9nc24fw1YI_1U9XybB_oJ3z1gMI06YE9HuY6X0rSX6RTGWoRbSrcVjRAxNfl5oEOjazyxx5nhEbl0n5gzjJExrSs1QL163_c1hOGMc5IR7zhTsXbIOqJUilXWXwW4BMe4OM69o9ELGoEMFTe9HV1KTr3MCGzYmQ2GZHVBtblI9Llc8fsZ1TlxSiNZJuy8aJF8fRw2mbny_WRO1SDPCOiEyaxdN8v1n_8F4wAk9AsC9ton4ZvR4gTwXEDdN3VBcA==`

* :robot::
  > If we spot the thief, I’d keep the sword handy and use **“kill thief with sword”** rather than risk a fight unarmed. I’d also keep the lantern on so we can see what’s happening, and avoid carrying every treasure at once—if the thief appears, we don’t want to lose a whole haul. We haven’t confirmed that the thief took the painting, though.

* :raising_hand::
  > Should we put things in the sack or might that make it easier to take everything?

* :thought_balloon::**Assessing sack protection**

* :thought_balloon::**Checking sack protection**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf528994448191944700374e81bf3f,gAAAAABq31KQcD8LN7YQh9DXvn3VmbWWe1S97zGLTrQod1famA_E8rTmJmatolXqiJ-vTt5OezfrctOlmRuc_3tE18lO63Vki3OX7nN3prGiQz1sRdR-Y0Y75hthaQzLp1Y59sWVyAQixdqPQ93nepERgbIcEFEHqeexvhtJdVWyTqeYHc19RGBol4DSS46ZrqqeEn_1lBBGx3NlkTjIgr1jdLfTsDiFsyXmfck0ynvsuhj9Xfwux5PnwG0RE4Cy_4n1uWqdyRGrTQuA3WEliJJzQDmYb30v32yVDtZO25DxCxeNVCq2W6Or5KsVRGfJT7xmcQIn-2ORECZm3o3l5izwZlw1lYWIHwObF-bSU9HVRhAL4xpE_b6XFeDlOXxTgHuClGB6MZlSFxANJ3XEHa5F0-K4bwy6koxRglgvK4HvXl4Aq-Y3Oro89Tm2_kRGQurvj38rJIsKQVmyFQ6IS5d5lcA024zThd9iNUXa2O20yc0PLBznsr_rEN2z3AsQMROFZ_eT9Wj2QaG_lHSYQtj5LZrwyPAljSIgUHkFt6jOgd2j3eS9zXQCdVDDeM2gWXpSlX321NTfXidzM2yDK5Ynj1I7ime0DQRgRINGufWKr7wRYbt4QrAzooz6XBx7R_eQtC3B_D2XMWrgvsqD3zlh56pvaVsRyhOk5ZmR_LPBuz_SlMQs-0WsWWw9Y7VSw5iwx-_lqV_A0GANifQX7DplOgbtPTQvtp9oo2FWN7Vm68FuL64sqhStF2s-o59X4p7ib_2IYN66Zb3NHPKbWlYaF24i0WdAW1vEWohzNwJS5_U0TZb6qF86rC3Ss02KI3HIR05p7VxponCNBjw54PXYvZ8cCbpDlW14k0RJxW4X22EKdGI4xo8tiEhEyJL6Gg-GKkGLEmwi6mWU9y9UthWqUFEkErjWz6eMIEeWhwRLEx9HNDTYBfdiJQfBo51MNO_VclBuxZHomKatcf1ApL6WA0zDdfvE0khJZE5hSsveQWH2yqR5c8HaTFO_uuAYKpGe2auS5s6n4phm7TH_NmzHFdAjxD4ZVCQVyIqKj56zA34hx2HGcLDuLYl6yo1Oqk1Wq5rGvnoWwm37HRe7hZPVh27EJxrH1a6H-Y41vEH_zK1OYXQqCe_NpeD_-6oAvstpIpBkXGsdGtqGFg45R2Wz1ABjHsYjT7ahhujqtEh9hPG0g5WugVvbFYMPeCE_HywVzDFK-jHsKxBbW2SNbHG78VvfubuY5e2uKx64bgZJkVUnmxr6yKuxozyflDvDWRpHsihpA3TLleN5_NfSiOzGn8obui5LUHcynFCVrunshfjnDhVo8ppcFV1b7FeM1TuOoRhaxwiaGzmanaeJz1zwlOfzBcegfp_fyjQnkNKVJC2joClynpveFIJq-W2McemJC_VEG6ECf393gZOzkLh8Phda2yDfOkn25LIG1GfAlxzI32Qg6yKQEumTcBFMiTNprf2pJoLPaBoRVa308Fi7DCcnl22M1AyGlDCDizL5J5Vcl_1bHfTP8c_PEguEuT69VHDff6vG9MyGno5EUozu-roeN1fjN4IJVnf35sgviEcKwiXBOtqc09ORaqwP-QLxZ30mKGPtkdTZGllpPaTqYoPar7R7S9C-_8etSjX7xrB412Doe7fHBHUBFTWpCn8MuTFoxURUM5liZzfztS1Bx8WYHmv7aeT0yNwtVzQ6daGICrKWZOD3_LprCdy60Ath58aVUTVq4AIT4tLEX_h5bSJJzrrq3mRukTzulsvmx2EDTJbgwlDfEGeK-4sQ75sxW5Ue9wND6T-l2lCal7Irp9c_oTwnq__ylepSKtFg0kKwS4Pc6ftVN_6Cbh-cuaWXr23xZflr4oGrZBrE4U97IcPQZhVdo6bKeTwoe2jU1K9eg_u4V2aEg1spmWnmNA6qkaewaNhn127GZc5jJA5FpDxDEUhIkTzWuxWQbyQrmkSTLcQrPmXnP3koKbFxmvG7aL_9x3ULtbIsn-xBIg5oIIB8PaJw5_xwVmZDKOQftapcinMqGrYQ3C6Tbo0J463UcX8myF3pLEcpmBtur5aaNEl66Z9bLQ0s7ek9rhas8OI-jG26FuRPA9E2gPXnfOUZK-oXkSiXHNt2M1hKGe7aTnrk4vgNhU-ODmOfQK06yTPzuFnKuKggSjeubMAq6FyiqncuL_2EuQpm_UGMSnnt5J1bQ_XDBdR6gkF4V-MM1exbc6EVk2etAA2lfMOwIAz2_QtnoEcfa-DK4iMDQFYuUN6mxMI8lHB-UDKgqlfGUBc0BZwlvlTXquihFH9W5-R-345JE-MZcJ2jN9g-OOcEHBnPV8c0y7BgJGvFTgTNVieYKQ6Do6_T9IeAOPSSS_XVyQVolKBNlFDnKfXvqfNu7yvKskMZrs_Lbb1oWb_YLURqKi38rLHdBt9vGXi9boyNCl4vaKgNBDFUSRpMpT8bwPi_Vc9_FsSlVHNy5FR--OY5MsIy06bIVkVQe2QhycxE8LCzcWL0RKcbrEnWGxD3ycOF_gYPKemCCvJMec8uiYyaAgQQPI_PQA7nH4EoBiLPzNLNYlXm3u0olSpCubKFI8aggxMVMw4E9EVMpBwQUITRBPnUavCDQZXS04VhDcU61oBvZiURp_jH2UZAhwri1XqwNdCwoe26DiqWYVnM--uGevTZgMB_nk1ub_1no0jNPCNFqOWqc7A8O9A2rRJ7yuJ1YpR3Ym-0ZntFUZTT79hon6olOLnZqURlmFLmoD-4HWBRd-3-Ndq-upZtjMlH0G87LhtGTrwKK7izJXpqOrFaaV4W0VFXPZ7V92oet9oPyfX1z4ivXG8WcgsKor1gsMRJ8a-9CAfPd6Lq2OSOasZGCuB1uocN6ha1qmF11vAlzE_qj9Kzgdeoqlngrfh9RiIbemSHMfNJjtSTeGPxTgF8oI8Dji8iUrNJjGZOxmkN9rHp3Su5TYMn_O3c0HrneztdOawbLIDd1AV-WTtjvM1modNaGklZv_hfcdwuh4rWu_LAsvFEhngkU8tEifepakizKtx4mjlg0cS7_7awCy1XIL1r-TY1PX7NjHJaiQB08GrYuBmJHs1-jv2dUBDYS3ym9I0k3hdk3PU6-h2uDMeb0xLMPrZwW0mlOgIfNCBFTIDmKtqI7QwV5d4h5dGCl6PiwjAZZS__JSZ0mdVQkhMqACMvqbChlbsahTmybV3KNN423k2cg1CIu3SjAmdfg0NnGJDU6jNd0LGCviXF5Izcyy9OaNVP-OyYjsRsJbmqx1Nio5_B8l6v8GPZqivn51cHui1jPzbsMtKojnjM2QJR2UJAlr_GZ0nFs7EW3fgb3ubSSbqOPBsmjbDYrU7k9gD_mnYYqHBJag1QnQ6j-_wCLgjL_ro2XO7VTe38dq4UBHQgUWByB5z4ydjTlZclncyqo-wSQQDDHf1dH6tWJWksA1uqMIx0zm2CUMVfvENI3dZI6vixFRNY73X0FCj5ynX8fkWQTmG0bXLHYDq5TwMBMFgECQqSpCTKjlCJM2mb_fu-9GsitkrmZOYEv4OMFRnNVH70RXGEfX8qb2P4d8vcXuNTqtB6qGY58Mop1J0x0SK-9yA90HBpECpPyjWquQfo2yHNxBgrzOf2j6rPbraEklDLG-3WeK3XwwUFxxhQbHAvIJzka4Mesb0uCBATdfGnZpFrvVZrYeQAgcjV_K1Nrx5rx3RbD7bKz-M5lK1PuoL4jtL_hUhJ0MVw0ct73WhIBCu_y6oucG8hLBeVga7a1KiGcYRGc-TZlTywKyb3wjs8jOPDoOLfRibtPhO1O69q69rBUDLGW1srI2VqxR9i_AnjSZOO-ANwXoloqGNiNKq8F4k9CKVuTqbhlLX3koPuOcBQJkLwE9NyX3nSSsslozeSg7IsxW3pf9fqVBQrUGJy9jKF7WezBl83Z2SeU7Pao4X2bnaQMEpkYxhWxPb8kErhl8BqMIJ7ZvIQrbdraeD2SSQqZFDfaf3ofKlZBo0V-3IB7RRWxqHsM9jTXVQtUZM1Tg7pj_OmR8vsCzjBqjbk5trHytLCDB7uEazuGIzaj_ak1ipKzsZnzpIjSYoruQVDUGN9QdtMcmnDfqJ6GOA3Tfzbz4YbzhTOc9dTFvYtHhe4hm19XonJN_CwE61Brav784DmFSQZ58YlZ6a56mLd1GYkMyBbApUaUZaSTHA0f61eu5hKviH79-KoR9io3yOc3ZUJfHINVQK2GyWZxB4GAX5da92wWN3bo2EQDPvls4PpO-CPlu8SZ606EAXbHX9eKJiQryo3XWowUYW8ENJdKBJijll1iBZkq_QUqmdgmWFeNrCth0pxe9Hvtz7s-e7lDtFOhk2v7vC7OozDXSQS6htZYe60D-nierpmgyh4REeNkyVjZ53NiyyapE-C3AzlLIS25YyzQppUnnw8irtBo6gmYrvlLHf6a7P3DNeoGekibHL8fagZmuRp_lk251uQxJelj1KXtvr-GRSBlfbTEcGTtpHqsdjSTnBC1-Nltqt65NACMPktL_7ukgsxztq3PNGvM0_e6c7WBz-ArQhmwQSdyXKykB6DG4FImq732SRzoQ6AG1WCotPhU1g0dO5KhtbjVz1pELbc33GgUymnUlf7rkg-81V3AYQ_hjr0Xlbho3LhjyUJxvGrgk-ZZXURJpgjPeHGCYsYXiW4wcE_RWKBkygdSrQprbegVH_dEhfTCawDpctqen7swzAVHw5JMyCyDeSQvd7rQHE9_QOEKZNrsJ8GojqRNA7sTVrno_HkHh7bKUEirjHkXbiBaczyNQOQpjSL2aJ7sGbAMQFedyUvETMloLYxNvDOLwaaUw9t4kAuyGfzFbtAryBIu6PiST6BSYbIggb03yYhf0jbcGnbtypBdAdgmz8CE_Mi4lX4jYDawbadvmH893JvOAgxqeF9M221FHp1xEab2PO_PMx0QhDIDS7zufrMfYgjsMyn2jH5YbNoVWZbVn_cNl1Kfce53-999CIAVItZ98WCyx2tg_rBA0KxilnxLubLXMEXKlg0DmC8RNpM1gpAxxetKFxC3JcCK4j8dE1r_O7ehYZqPMAKvkqMu9OAGLwdnuFZaNMZBjploMm_ACEWWSUxJhEQBbLIjp3NkTb2ISIE09U8_sgBzrKLysq9qGS0UblI0sT4m_6MkONzddgOUir-HOkcnnhXEbxQs6B9it-G2V5ZdTemCKpTYOFumKikA97PYCvyx1qT1KdTik9mr1YtpoY1yR6m4eU3QjR9wH11EKocm3p7Y2cw68lXNPnaP1ldTVf2Mg8v7-M8nighxYmZdP3Z-31VV6RcgF3z67NHSpoYCgHOJFEWY-T5d3T4l_opgCMdTxp5fnMIXKkLNjwSB9FVzYYwWcaGlDoO8EzP0tdAw_RPR-TSRtHGQMF3U9jQXIFlrQvls1LUZZrz4NpDBWKKMGWxBcOO7g-sX0ChzCveeMG_rxNzToRBTTYHlp0kiw==`

* :robot::
  > I wouldn’t count on the sack as protection. We haven’t tested whether the thief can take items from inside it, and carrying the sack full may make us more encumbered. Better to keep only useful gear on us and leave extra treasure somewhere safe—then use the sword if the thief shows up. The sack is currently back in the Troll Room, so we’d need to retrieve it first.

* :raising_hand::
  > I'm just worried the thief will keep taking things we leave about.

* :thought_balloon::**Clarifying treasure security**

* :thought_balloon::**Clarifying trophy-case storage**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf52b6dc088191915719a497458c03,gAAAAABq31K8C2A2CH9sH2BYWVw-2QBeX-o0cLmyqJ9h7KkcvQtmzk0URH0CAICMTuAG6X3voSe3GxjYU3UcTkEigQJYUuNXzuOPljcxpu4MgJ6BQcyf95LnaC2lSjU7Wvpuet2kZUd93ZpdtlfbEomhjuYGUn4tDUACEah3Iq5hiDBALjHK6Xpf_nfYwfyCSiqjXeVuONfWBYZ1VaTEwE6R6lNbZ-2YUFbWW3-_vNrUevo4B3cMaAjwyvk1ibHn7EoFbO-Q1GS32w0_Zpl2pUlkvRVUIgezYGlgz7dSWVIC8_mGAIpGWEobqJyGZLfYtrBnB6nmiAXqXMczYnLOi6YHTWRfQwAOtRdY98U81eokNESzDQe8wUwTTjtPKyLH9i8Fy4RdE4ulsp8C_bq0Er5_JoBcPj-l3cMMAuUlfKfnQ2q1Z2bX2kD2MIjDD1p7ucmm_bN6UlcWwNIwGmhJV5UbssmXefG44M99nh0zq8PuGy539qQpRZpYKjLimdHemgy9PW6ABhCu_S8BemSlAws2JJIXlEyyN1sdOrTeN1F9NL6d-QQVD8OFAoUNON2UkyVw_iC1LCHEw0AKT-Qu0YaAG0BWPxMMUwE7GQnsLEBJMxTdrHnoMr9kBCMbDKdL7CRoAVXHe1Qn8mc1ZbL_9iXTcoYtVFlCo7qOjmPztXW9Q6No1zM3IJc9VZPKg5mv-s1GieajUEjF3On4u_HFp8bXmjKWFHYBfRHe_NBqU7Cx9wdXKgXDE069gdbcRJ3bcPxSJ2QEFJ15I3vZGQIZbxmmxQa7g-mrqBu-lusqpPEwRsPMNxHSkfSqc-7jSMNOGp0nuq3zBLX5n67Zl7RkRQ138mOvB-koGDpmV8fCd2pzxVtucGyCGAU_UY5-VC9jO6rNb_NQFBDsfF7jMOGUrL0rxIkTc-E-2HHQJcC9efBkmHtVAonEvfDooFPch4jtlWz5z7jbp4xx_34lA8hr-qRrhxKCTCesRqBkMnCgeoqRgn9KuTQ4LPkAC66pUI2MOFdyIKRYGWSlfUqRGrtzrOcGpga5TwzV0V9hlVu0wvQaqBjALZ5AAWSxFtMOlRVKwtH3oLnXHAFH2B30fHD38T8VbjEcDEioRcA0JMiZrrvMD2cVLMvQ9_kHpX3M_LL64Ekdy-Tb9O54qZnScBGjH8NLA99EWOllqcegI0aDD3kqzZ_HOZSOtGAhiLTye217NhEbgI2v3PWKMt3bjRJNPi-zhSpSt9oflqZPYZ05s36oEH2AR9KkYcSDMXxXTugf8hoBuKhlK8zpzqk3BHSUJurEKa3nwLCPkYIcIfKQ2e6FHy2QK6s7A-iEllc8pIF1BAzT1ReeCdWd_G20GQhlmS3e6u1tiY_B6H2BEVQrXyVXICAbB2QiST_XfsnXHf7oNr2Ycdn8uxK70g_lDs9YEJjZ-_TqKHV9w0_hiVMrjw_5A_JDHkCaVPQRhfZo7B3l_5gHc7VjR4rB1Oejy4A90Ga8fRRcKvMycH0aVIViEfBerk9vstK6JmDRV9cC3i70z0hi0JkRQADdlNMc5j040372m3GrZzsjBvecCUuYSn00FwWWffTa9gDsfLddKm8NbmN__N4DeOloFaFocQiyuIgD2TKEcxWL0IsjVo53LMLTZE91R-xbVopwwfkKi6iTqHEsLBiu1IPNdOmolveqIy6YiQoHVpkKyMpN6oAvnOaKaUXSCMPzb6GwmCVu4bQFYf6bq-k27GNbuR_nHSMFku7MsFHxKPimjnmeQ-mgEcRGCJiICPDgYiFql6ihlgq1ylaF0_ahhmxPyip0AGIHQeT_lTCJ2xlZj7zM9IP9hCqZqz41Vvg5hwdn9oUwWPG2QB_m2spz4CkZJ7VZinG_sJ5DFXRjZOq8LIA-F5pRqw1VqRG4S6lk_hMd0yJRjpKkugdeljibJiRAfsVbsTh7sP70LQ0Los1JY98F9OhPryWjzzj9uHsRLeN-CES8GFU2VtSSHcHArDAfVTGD2I6E_i6YRGgAUtCKqYwEDfXIqWas25N3e-9NHOBkyqidQE9c5KlLQ14-jxXpWpbmgozX6_6dGMM0K_3Pn9fO92P47hGSCM3gZUlwQ-xQdDI1p4KqR-qT_TDfdtcOiYKDZlgZpCdaxcVh3flNZOa4l_mA8D83kJB0MpAzFaNu7IDS_NrmO4mVU3y4URP2aj1E-lu-D-faaPcZlqKNknYacSlol4x7SpboFCn4iwj8a941HpXx8wC9nMICwwg30wCeYF-EixXV22b0QyW4oeudRBMbwrAR8LFymMY4LED3199ev93YUx504XHGAS3nkycewQotpMvjTzUwnhrNIhedD2Pfmw5cy3BDKPYaNX1mVEFPONiCdtSXXYJve2jvTjTV8o-FyZlgg40Q6oy11iQnEpHQmpVGS61Bo-L2icHQohbUbNHX31DkV18MIV0RuaDMDO-TCswHre8qZ0WE0HuCRMBb6ACTlNQmPOWy0xgRGmtWLjv1m-GvSDsQRHWhp6-x2dzn4Z042ws4bQFa1NSFO-cjfQYW91EVuzRxeWD018rKuqbfAGRCvHkp7-dCEIgdiuOGgrrEIn6ds3jw0g1Wxj_g7ILqgqdygIOE5QL80k8OkB_aaeWmqrRrxvko4RnGjhQQlB7PFkI-tAEbrxn7rcm-vlezdeLkZvsZB7pR-MmzFBLoksi5qpfFSDcwjHgMXRFbK4XGoceDDaNwZE3LLFyz_67NDic0uSejWzFCAuJJSj_kP2OMOxEcTkzYtp7d5ewA8tfpFfeCM-G1OvYbOGIz4mjJGUA-z_IYwZpWf9-BL4RC7XTblPVtf8L6bN2a4OMgbCROBlzVNKvagvcfbwngbQV0I2boAiWtfMRfNMio5H53K4fIDTLiognAoLb3RdQqJbyLG2wgdM0liqNmnYrokVr7oC_KhV9gUbtlvuT60DKwVcCO9fBeFslU8BAQhgy83t0pH3HnVJVSy_NeF3w-JyBaULeKaDXOkns3HJkMC7cT678AjCOWXwjyYuyl9xUQOyMXRoWjU_mmdwaWMzJCdqHzWGYueA6RC2JtpcO1NkHguXC1ztZACDmYWbibSQLN-Gr0e2aRJKV2jJImwPyCi0Ja-1vzuaHwC9X7PlxdfXg2NrnDEjpGBGDpGDyy6U1g3YRXVaI_KnmZN4tsGAx1daXGes033kl-z7b3-KMkk3Gen-UhyG4rjCCZ64ODS4XCYL6C5FSojzqSgivemO4w_9SgwYyrbxKqNcJcCw7E5RVzUR5yJh-0PKq0q1n75Nnhdn09mO9_S--9fsOeawx0vYyHpV5HKejhSTBwDYr1z7a2X2QYec8F0QHZ3rW0nuuuzeV88wNVVry_2HMpGuu2cjVGIlcpTJDWCjcJyfsg6RBEk5kVpvApbX5o1YhjTn_nWfEXTrc-JhdmU_yTdERVAT5E4cS7U2LAfhlnNaRKOuAM9pODGxLNDGu_8fHfeJc4K7uQuI8pkJOOibm08k0k2ianBH-YK6Twp4D2RHLAb_m4r6R6DromKK_yF0GRk6MkKe2XC4VzToSG_MR1N_SgsLpS--akrCdYxamsSLfxgUQ8u5TSJaIYJslr8Hzw0kiBJTvwvOfQdVLw5nhT6eozSz055baEVk95_tfibs8wptmwCoev00_1Vyy3j0aiLnA-1k5pw2XA_BP6s-09dLhS4fA7AcGVMEk1S2sUGoBqjKCliU1JNFJ90YeodSJZf8oaz1MuRZ5SBWkDsiGC9l_KMmmx4W1BLZVqPntSLBZhyKghsDluiGryJ1jvw0ZKr2WNKfaZtz6ThaPjIHk6KIIbfSB32O7j0BVLcp-r34FyhuU1S23EzkY0kxRIG1VfspUOx9Gn_SEQxNfuhBnZzlcFszCAE8_bAjUs9j3bRK83UKT_LEN6mOwYPUKvIgk6_7XMw9YgC9IqFqUEVqPoQVVl4iXKdFNw3jy0OiU5a7lbT1jzf8YmwRLDI3swzlQerNC01wnjDDmDGkGdYbYzIAku8RWVW8Q-qK-LKTo8u6pU6Px2v2orgXVV6HZdvztWc1o4iTSDT69aSdDPFvYeO061obcJFEUqO1-p6e9bzvtRnbMmraaWcfRW7ndbfPnjBo4nntgcUww6i1C3Kk7KrhmcE7nR1ae71UEsEmKCwjPn3GXrSZ-KbPP4ZMRTdGIe4YuibK-6AzHsngFE-r5jNc2u6Pib9fuHTDauzWTtHWJkyWLHd6I9V6slfZusje6_j4frfrxFw8s2sum9Cc7op_WDEC-31b8I7ylVclFv-vsjdA0XK3eR3CL2jFNH81eQesUI-4w3oIWusliLj9CuSPd0YLmIYJHoc2FX36H_S_hf5JD7Bunzik5XwfdZQYSnTt6xxsTutv6gub8axPKOvJfZQKMbZ70ERwm0djCfaLOcEpsm-lfe4OWluqeOd1VEMiHWyFDxMwoNMPN525q4I1Khlz5mEkaxG4da0PvHsTLpNWyqR7Gp6tp_vABQuETzkI8j0E1iLYrXomdDipmFUuDf6NUSYvsNBpbIQHg-1xXvB2cFvqjpq_PYiVeabin6jurieI3MxkQmXqwbs6Y7M0yWU9jj3Pdl7Dr30GyZlnkvQSH-h6D8jaWC4eGHsH26v8w59et71Mvz5r_tsw8xl0TzP_l-JPY3grIQpQlSb-NKRUHwwQDBmWAuwapKQWf6XoY-lip5k3pa3LJQJ1qVa6_L5-NxlQFGO4iW_S9cvhP4bcSt4FuvHPQDwqjJkP-tqNRzYlrUD9jvc3JcG_8KeOtIeDDW2E7_IdBW_bm_t_2hPu4lw--Lz6DhqsDRgyhlso-NMyqADj8wFyQKPFeUC7awsLeFBp4yHISGfqaXJhFUYqduipSl6rZZ_aRdRY-7DkvjwbwnA0_6gKrMT6ku6lP4j3yH7MBYQ0tIHG6neklQfjxJcKuW2_LL4el7v1JOokTpy34pitjAE_78P_PDhCNk07lr3HY_E9G-yX8eXe6kU0b-uyVtP051VrGm1WQ82jrerhcWatePQqw6Oj9S1R1mBxThS1G9HlvRyRQIWYoYipX-acLLGw6Ca0sLPnufnbBK0YS2a1VMamvxTWMW0VGk2sCRaZygEMUQ4G8=`

* :robot::
  > That’s a fair concern. The thief is mainly a threat to **treasures**, not ordinary gear like the lantern or leaflet. The safest plan is to avoid leaving treasure in rooms along the thief’s route. Once we can get back to the house, the **trophy case in the Living Room** is the proper place to store treasure; until then, we should keep valuables with us rather than scatter them around.

* :raising_hand::
  > That sounds like a good plan! Where should we head next? Time to explore?

* :thought_balloon::**Exploring the east route**

* :thought_balloon::**Navigating toward Troll Room**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf52e4055881919930ed2673ca9a28,gAAAAABq31Lsz5g_3b-ahVnbeEEP56xdBoJmaS30Nfr93A52PW0GOOVkiJXjvvZIms75WuopRUH2rejFE-K2au_lSFql-YGQKkcpteeyzdtmO_vu6GBIMNBxCXtFCZgahWoRVG8ZGkHm778yHJUyrcJ4-rl3pRgHAosYGnBnqE7HBKccWTZLwClC9CjVPBUqKqJUtfn-1OfszVwR-sXmTs8rEtu14r1VfIHAbfyEB9WG0LPH6SWzDcDGougfAIFkftgdqgplA3iOLyV9IwUwvmDYqZHc_xou_p4IUG075LE3mE9DskboiFMFqIdAv-DhzrKa1Ni19FtXtSkiW4_wBARdNKw1ezx1aO-2wXKdOHGY7_jS53f5RlBT2NJlx0908qS-xu1VGZtt-0jxr1f4ZdDDwARPB05U-pur3A1jn0Qasd4VVg-0zDJIwK8gR8E1bXUzRJPIVbxEXEkV1wryZhsgHerUZK8pvn3u_tvygzc4_CT0NzJmv56tNwTC5lrhCsUwBfa4UG653mahHdY9tRQRkx3sgVjZjgB5ZR0KIduo7YhQDDXWUFr_UYMG1MmEww4c-fw6V9H2KuIQ5k7F1s-zA_9vA3afuLzcU81yWf-T2nQMbIMOT_N9MEJYbzUfOJEhhsUXHpLRgQeEQpVjgpn9nCMo7AJb8efzeBq0lmilqNU5WsbexSQpct-8t86rsUj5yLGmpgWmy4PW7wMYkIaH2h_v2eAV40YQQA4sabnhGS8-UpMWjgHS0KWRgRP0P8CASBzEsDrWeNZlCIX2C1BH4uVSAjs6KKCBhfSelprz5Uj1E_gvzFaSwaKZrjLIvq6gUgoAJz4PtgKyZD_cFHCni-KHlPSYl7dsD5vorW5cCch6Cfw19hQLkN0CC1BmCPJaN2rTZas9NDhNt3NmjiXlWCMpuRhVb_DAMzkxSVeMBcuuz2XCDpnb-GU9PnF0HHD86iRv8vmBaBEdtOR5AMhcpPiR7OOu8pPs_bV97pBVSx2Im0zshS-q04_hTsnS6pj6z8RyWTxzE_vBrs_nW-aqTvd7qH0B3jTeFTjj2NG1Gf_kldJNcubVUlvBv1X8AEuDjzzyirbvC0DExUeGA62CrAkshi3r9ZqlzxtzziR34yHqf01VeZmd3w-S6hCHYtI2PADFeSHNRUpZo-00mr9GbrpMtPtsGnC5NZpJLT8vEkTCBJz1lnk08dFGpmgMjbjnenREhHsY-xbsuOUx-Ihav_qZegwdki_nKywdcOO_rxDepXoWWsiVXOoN5tZJHP1jHuoF3BvdXTt-hYer1Lo9yrhZftn0mQsfymRBTmgPd1UlqYnydXDm8C6hOB3ULASGO1UujqcKn4DHoyX9dgWfnJLHisRMgb9T7bDMYs3aYQ8GxknCx6P3LIe8SfKrq1DnKJkGOcfvlUutKQlmHC4xDNtzSixxRjchIRosAbMWO63MLei7_eqW6ihlPGZcwyIOlJu46eJcv8sEMIo6EsSdEFeNiE4Yc_EsTd14k3yK-aA6yG1t35AZGTyT_ay-Y2K0XFQPaP0poD0k7ZlF1bqixWdUdXH_Ka4xPb3lKxOGVuQ1YxcOyY-NXgY_UzgFpOZUBD8Gs8Pp2koEl42DjzdXImyJBJlqb0hlo0FvuwHNi_gfdIbgWmsEph1SLsl850FsHtgBdyx_1geeBmQqpE-y2oCoNGusC5wBcgFM2w8cuMTTDa89YOmwAFqzTdaDYGdEFG1_yDoeZIQuYfnSQDUDrHIPDeyZwHoRakfU0KS_xl47hLrWGeanKDS9SmS25r_-_rbVEmFqGXg6pqmMindqwF0txuK6J96DeG_6e-GcL7lgYcTsV9w5AgJzFI6X-B_uGKFn8WRhj3nyMZM2VlssZF4pUbLw55VUcw6r9kagj_---zxucrzbeSk4W5zGFC0Mb4HLhfucenRHTy8nif8sI-9DQPmZ3LBl01GZmeRNGmGK2zhDqFzsi_lVfWzmP1Lb2eQFGWk9Sg2MHS_oi-0uZmZ9Qbgug2FKXBgkneXwZX7XP0M8CC64bUMvedidf85VzkU5Ovleq0cWBoDUehFV4vtabB6c0kDovgzL6kXSB5xXASTkYh9iOLXWZV14abIxi7vwvmSz0eV66Ax5giM30aMfBdDcLnCI1ZjHqQyrkmbub9UNaLK5D4Loia7FUF_dMK2WseL_t4xowuxN_1EDHj_ySK71-OspgaNBlFsTqHlM8Q1_I6wu0EU0B7P0xDUu56lJFD6zyt2RMQjrVSzQblqjNNyE6lBLpbceeZw1SwIs_LbJqSPGbwUOG-ERQuzzmX1w9Jr-jx--1eaBBBHDe_daEM6n9wq7aKdexKTiFmLM2wj9AHAIzz-V16vruilVD4uOYvNCH_oNPr-gSOfVoKAiG2RzUEmF2Em-pfWVY2iWjrtcKRjGCQJsxZy4PcxKRoTFTEu7znCVnWXZdYBHoqOcDz7HLPXHurFzvqtzQoXrGoVBgDRnhWCplC3DCHNDrx90QzBBJiPQbWZnMijU6PAPFIa4pF8ii3dYnmOuSdtrSLcS740LC52dl7Zy2mHx503wHLYVvELQff67E9nsIsqeBRf-_BCQhMZt9_Vt9o0Tl7gr6gtVa1aLEejCBKsfnNUwN88MCrWw1noze1eQ15i_2qJmQMWTf2xo9Ee_tagcDpRxrv89E3Yax1BkWuyyYTRtWIFEpUk6FOdpg0vNm1eCRj0CpToxG-LeP-It5nQGtAyHZU2nILHFBdlBIayC1VEVj6EbMmAdnfWdxyLZo5FQ5rJviAcVt1M6XS4ymSEeZ3vBBcSBafMgMz1xoCp4LvsaLH3e-Un-S-a87JUJBRHw51PnCpiNhswemcXUXs3l1VBp0u8Q7qy3RJIC6V6kXp3SRodloGnDM8OdOIgvsLuiMdZTT6W6c0C2bkfIgs-jIUVIs5E_S5Yu_kSMLxsTtadEBjdr3wu2XN1YpEU_4DdhY6Fppjkd3ipAgFdHxwOD9N61bcto6BpW6WMmXZ9h1y8afBtxg6QT2BE5abnV7HFQgy5XWYi8Fo8CoqBm8GiHraV1S9S1s8iWL705pSw8lY-Tro9oOC3XkrgAgN4-cU4zu812ahX68GfjrvGpzsjYBgBn_Awe-7cngosf6VcX03T2vHqEd6dBDZv6OB7A-kUuTASdhD5TXho5n5LARX8gIR0O4OXuMtm7_VnbbREDMy38-droCE3F9DcKM-i_xqQ9f-p_UmLPdaz3DkNhGmV2GFX-X3G9rnSxTQsYZIXJv0Tzw8q5BvS83BPtTyvshhoBKdHocYgIriX8672w52kxwkKxm_nChm2HfNydXAmSZ2uSW9j-ekfea2QkwjQOTRfsYappb_khwtsVEwyti8A7dafrnuiFqyyNoDpP6imY2H3hgLFMbDwXou4VZbNcF-XqXf6lLAH733mFaZpJBvhCJ8AuvEKIDPtGtSGzPDnXFKxRUcNpfdWyOtqllQjkHzHJLQqWkPKc0BMnMhJRcLXDm4tmzFDQgx4hQ2SYUZS33BV9yOLnpNbohrLa6-3LmY5_OtnRAMNjLuca00oeH0GRGXWN0d2upDw5-5h7NYGhSBSSQmVrzsnpkaS6l5V4Q03ZqIycXurnbhLMco0micLFmY3YdXaucwYDTx2c9r0uKOhl_7MVzENKWtvDss7br-GYW6ppvzkEqFhm3kIc7sDVA4f5PXodf-DaylC7u4FjRvmjQlFRZBoJuEYoGkAAqtpQ6aAhBTkLjmDDKnePDJ5sZhNtM3Ep3Wh7gN1ittAiBWT4EQoFgs6xzUikGixb4BIpaR6YUgvu6ohHA6YAuUVXIHszB3XeloWJrt0OkzLwJ6YGJdDpAyKqldImmNJCE-toqKjgydQX9SAsiuVjkb_SuTS_4_UN53r3Xai_LBbbzkdsFn84ZVx7gB0LwDVyR8lwkF1Kzw6z10Y86tPh5dg-UjUURrEGIHends3QiRdhk9K8BHWk7G3YQVk_Ua0-Av-yH2q9JEELcrPZ2bKRaSobuMfaqm2NKalATb9Nr1-KjdBHNdUPb---w2bQ8W_3MrjuWO4vZWIcmcyrBJxKkAQ-Iwuo5R-BtRYdBmReYmHSFADeSXD5lo7xY23LkGKYZTtxdLuA0nm1xFaKg04TAzM5JGaYrSgIodZBFXymh6YyOn5V3HYhsMASIpNi7C_YCAkKXrX18Z2kexWyPjbJPaZE1yMNPvlmgkGJsfQpi5P3QgoAYno95B6-kIvW7ygkPFstDrs1Dr6bUBmf23d6uQBc-U9GPApEn1dVCaIdoJ7NMS8eY0CRM7tWBnotgTXumLlTrPsodrMDkifqr9UbzP9LyloR3Sn3hFjvnx5mlgKyxEOgewCXun64goWkPM00H6pJA3h1MQFos8BBG-QKLzafY92OF09j66pvX_TPCh_2HlxW4mKANckbiqLT9F_HbUditOK_oYusbY3FIzhhm5vHof-s4fRJPlOyzy_ndN5qhRcZGEyLe4230Q4lr5DJVRiW1Q3aVntf3zeS35CzWCF0ZWXDZelwfQFqq6JsYL9rflqYiXD7C4GNLSbf1BcWUXlC_hMUI7t5bd3LGJSyUNtKSHUR7yq2QvGWyAuxizBGzPJnDw1JnH74ZQXLzFi0RBRuVrlRgX4oRO6xb0IVHHPcIpvle9g=`

* :calling::zork,call_446b558e52df4dbf8bdad1fb4b188b4a
  > * command `"north"`

* :scroll::call_446b558e52df4dbf8bdad1fb4b188b4a
  >      Cellar                                                     Score: 39  Moves: 52
  >     Cellar
  >
  >     >

* :green_circle::call_446b558e52df4dbf8bdad1fb4b188b4a

* :calling::zork,call_d141ba077c6345f881cbfd7088bfd72d
  > * command `"north"`

* :scroll::call_d141ba077c6345f881cbfd7088bfd72d
  >      The Troll Room                                             Score: 39  Moves: 53
  >     The Troll Room
  >     There is a brown sack here.
  >
  >     >

* :green_circle::call_d141ba077c6345f881cbfd7088bfd72d

* :thought_balloon::**Exploring east**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf52f3c47c819180255905f2da03e4,gAAAAABq31L1rITbYoapuoUOwPhPb_5TCv1fzue3XViijGkk8TkIOTuyp3ZmY1RlUA48RltKnb2flxElynfsshF91oTm5dLg1Wb6_mWLaeVTmsK_0p0-FrlOCQwWjuYLChEiXTVSCY4jNydkNuHpoXBK_jKvrAJ9Tm0Y7bG9lKLJGll95qtSI77G_XYEKUWmp5XrUq9B5Cc7wpSZS9jDHkXfJqage6Dk2MBA95eAriq-5VlRdCaU--uJW7dKitVn9yzXULJ9KHvMb8H3IzhKfmtAyGu2yJ33AQWl4_x3Roa5SWb_Esn-FPf0Q0DZEbWqD6MLdo5JuMFAiKptssHvbvojsevyIwh_qmRNLBhIuIWqnNeud_koDBnKLyXx3VeV53QFe0kF7uNKVdyQOZUpNYyPvsgkcdDLf_IK3ZzL3cM28zgUyCdPXYZkvkUdoPBFDctLd2my45ppnLNoWbddxbuJtNhqovB2XLcSWvXctoEIv--RMjNA0b99ayJUu21kTqwVz6lR23M1kxYg83U7OKBX_5UJ8L2ETQtmV9z8LoUxSnO3jMGHAYLm0qQnJFYgOTTP5eaH1z2qTjMmc1pKiVa8kSrCZP99cYoffVyildq5Rjy1-vWoJnTzGDSDj0y45VUuf1l0QAdGfFznsNwGkPG34aRCSJwB4P3Evw62K9PyAESSOJpruP4_JC6rqIkgLcpraps11-PfnpwkkXM4fJqRPSYUY7wyWR4nMugf1WMcLaDo6wF5N2bwrLBuFjrPRNNGzeUSELdOSzwJPb_ySmWVXSndSikE5CpS44oONZQIli2pfBetn25aivYy7sGu8-Mtb-H3sodktl0jL6m0licDDQkh1QhGSgJfTJ02jOf3z79zZqKv0Lf3ZpaB3h_GdEcJug1aiu1dMiFfB1a5pRAiN0xqK_N2BkteFSqrcH3rOhtHBXxGmZLSP0N3nlIQUU7AmAoqrBKOR6CZF2jr-hpaaILfPuqayqG5VfUoRw7lETHZLETH_7eKQtRnOidHspxnpfeB0K3cu_OvOz8X7ky0vcN4d6J0eJr7rLR_tWhkTVR7PtYgltFbrwUxOKXbS1C3vxqVXS_B74JrL5d0ZngMihUMOd1m2gXfmrX6w4Og9vfVXqqCsqXL6J_fKOqL8Vg2fXF7gaf1mI5w3i4fmvz1NJas4rwdPNWY8t0ow7q770shikUOzulTM-A3NAznozVz_RkcokcXArFGg2TCP6i8LgmHy_4uOi7yTuP5A1EIdUZB7WfxoExy6u8G7cJfPYf8b9nZ9GuqasoLh3cM154ojVBeANkhIDsUyC4IxaTcynsXpfih3-zL3ntX7LXEm1h9hiS5sqKgdFHmpB305Ou-e3TVBWLEviEvpxrnKshPbjdL1fFnkVQvRK6R4ok4tRGj6Kr3hMDO0G7rcAHbm9ET2K975hK2-wtZX4rI5jnqDCABL34UbRratMvMR_cc6Ii4ktJSfNs7vR9vt8bsqHMa1THUsV0_81kFcgVPEtOMP6IvbuGVcu0wksEd6m-Q2CQO6jwrcn4NsOsRgfLaM4PowCMLN-VhbNHl07vhLtCT8A9rNnb92Xm2W1KzfCjhe4bm1I1r-Ku2EbAeYgza4YpLJt_fWOwJcnEEX5dP9WpuyCvRl5r5ybAKdCscApRcI_OuXlhHFzFaPL--mcwwLuztIEn0L69Rdsq7Oi6_XGkPFgWfodMWhrKOz1J3Xf_ktST6BLrE1xsxBZ4LwYdW7F67JWA6PMq-TZfdCZjc25LQWy-e6BSf3blskujnwbsCaw5uE4vVVPMENvb9zdgFqgyE_zOfZzGfGRp7Ti1SLaUFWzFOUUUIA5a1FimCo9yMoOFXbIl7Vw1l`

* :calling::zork,call_13a48d10a1624c4ea68a171e3abf062d
  > * command `"east"`

* :scroll::call_13a48d10a1624c4ea68a171e3abf062d
  >      East-West Passage                                          Score: 44  Moves: 54
  >     East-West Passage
  >     This is a narrow east-west passageway. There is a narrow stairway leading down
  >     at the north end of the room.
  >
  >     >

* :green_circle::call_13a48d10a1624c4ea68a171e3abf062d

* :thought_balloon::**Trying east passage**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf52f817b08191836f59e93b48247f,gAAAAABq31L6ByUPPI-iVvSSj-oykMDydF6XLHtqXnRQNVAclppZn6RWy0RLri3yRBqETUXYmATaGSjh-i93xvo00ZzImPzQcutNPurhqZCVePx56umlCzSwFEJRpSB0MvMy_IHe84QL_kkhzdbIk8q07xvn_vhisBxsbkqpYmLec_FHQguxHVia4-xHp4ElriKvn6ycGkEnp30tDcvlwB0Rpd_ArbXzOC8zv_InDxv4AMX0h4TrgDAXvDItos4mffia6fzvA3_nqQIXoDq5qYxbQNPbTdMZ49Np8kqgU3Xx6JCoGx7fpbntd55JwRD2xlG94ndHkSRs5SG1OfOXzynZb3zHThDxT871Y9YYdc3IZBexYmKmoxW8pGjuGLBON_qcr5oTJK7E3tAW0VdOH2Hl1Vt4dnatph5hLTDmsWxOmNNI9u-q8IkZvXE94cXNhGIApYAzYzw9YuIy3rC_Zt6F-B6-EY-1xKtewqmqLfwX3luHYb81oRB40hZxvf7JVMYRX9XfXXPqwRjJEZ95lh8HChajqLM_naAsfapuFxV1tB_RlTGvIMEZhAEfITV9BaJVEnQSJ6MWfW66JpckIwitlpXp7cw9yK5LWiOBjziKMzQkEVD_IgZ9rJQA5ln2LciPaA0-TP3AWRbl-gJw7ZTQKwsnNW9brsF10dj-t4xq-ZhHsRSHKTCdY5rLSG7lMNAiP4zU6MvGFQqFpdT5X4pByVMrb4NgljowLJeSbVogSmSEzchpApcVZKUNINlWx4KREaB3RCE0_qJ6M1xlzZFm6k1UpXSuLAiL0J6Ynu4tuIoQUV3Qkx2doVLfSZJF-wCN0x3xEkGqfu14sQMCV2ouu_DrMEMiMH4UWWQv17uoyOIUzQL6QY2h0BAAhNg6DUbWhsCy_SlPrlSpK5H3HYhWiw1k31tsaLpZLakgye7MkB8vQ3FpA0QYLAHt2OUTgVqVaw86xOjRghm6JiULnR_Lyw4xJM5t7AafUFW1tSqFpq6XALBjxOnEI9xIb53cYAMWQuP2pv9P4A2n-B1t5oBMPaI57Qx0jzkP5RbNrxz-zdbw9NIUVfIUR-ZiVzHNGOVpvi30cUOcJpfqKrEwalsxhdk5Kp3_nCF4iS_4Bxss81qgQDDzpv0JHIxWIJ4_ZkMQpkQJbOXZkRrEQM4klBQEfNIWCWTLhy3HPcG_hEud_VeOuBNHclfObuvXC8XJ9vGMV7bMsp42Ofa09vpqDVo8EaWho2I7eihnvHsuAjt0SfFqCz3pd7Pzvfm3zFPLxjMbwhB71T7lb6TMHiPng8Isle4hZy5JdwlxlavG5HcQp7uhBy3fpjIy0TRLBjOiQ-6AswIlJ8schqu4wxGFRzScuUf68a1p8bP49D99wbO9OaivhrFIpbJos8GzvpOhi7giOegZClVxWWkigj37snlBny1xrBg1GaHxr3XDQoyzYcUcSSfo37MkTSYDSqu7a9QUIzwzhgH3ZmWlaam3HqEx_q2nsGSVYQ2oEr-1cY_BwIhaXj-PoYKE2lAuMwIyYuU5jtnT3S5HFsOUhtJZFlXpp15llLnzeVxzExelLAIjDjy3XV0b_VBlOAIsSMqE7TSS9sexIThScP1k2enI7fyD__OZg8FRYn53MOEJN8_qrOD3-OtxZdrHRR_45wcCPChA0UpxN0eb6d2WgIPCDnE9DcFg0xndA7JIpRdzejIaUTVV9wXyjuw4rFRf8AxyUKj5QoXRz0XlNIItE03u9JMpCvrBP5yw0KtH1GX_SEyCvHc2G-RTFI-dzF3wUcu6M0f1Q9HX9csz6lii6MkQyHft7kXiHcm4NKLTYP0UqS_vN58AqRByyOM=`

* :calling::zork,call_69950a574d8c45d684b66528c1844d47
  > * command `"east"`

* :scroll::call_69950a574d8c45d684b66528c1844d47
  >      Round Room                                                 Score: 44  Moves: 55
  >     Round Room
  >     This is a circular stone room with passages in all directions. Several of them
  >     have unfortunately been blocked by cave-ins.
  >
  >     >

* :green_circle::call_69950a574d8c45d684b66528c1844d47

* :thought_balloon::**Checking the northern exit**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf52fc985c819191069a1fe4646c69,gAAAAABq31L_AXjjzFCl6zFYHZG4J8_5WNhIA-OIJOpoLwiXyjZPxtzTbUXY5HUjC0ZX4v1c2nngZot1dTEgM6zakkCJbwkzRXVrg16qxapoRa92a1mM_IccQ4TeopXk77dkyTBSrJkg_3Y9BrklfcnSNCMN9cFCkMOZe-271eUYn4SHFXteiUuCx1JMGk2o_6Iop2bzCqVIwZDz_sTtyfOfTeYaMACpOy4AzKqiTfTZmOEnn27MWfmvyMI_nP77tbNNl33SMG3ZSi03d3YaQq7B6S4kmzoaYlHQV8lhLZLcU6K9r0ogigUBjMrVsuIe_83aJ--cx8sMnUFe6_SYzwS7uIbDi4OPhFbyVzk8h0F2HI6IxX1ZA9kOgLB0n4bV3YIAqe-vBDznlvClDXSHDsNjKACE51eLe5XLFuMaCulHoNU2dFLSiAW3XJ4nfUHr-6Hh0AB52bXnJTLI-IiUquJe4LVkPSimOOItkYtDrj9aUC57Wf4IY4llFdnpA5dyhD-pPXOJWz2GMCvwX6iNLutlYParXsoJC972HBSjSBWC5WRI8MEPO2KEo6fGc1O_qboWOsT1WYjwpDeme22o_Qkf0OsYWt7pgGrEAlZ3b1Ipq-fnt3cCNBYZUyfWH2PQStZEALC-_Fc0jwXbQ_huDZZMOzNIr-MWHOL4-OB4Qq8CFK3nnYJxcBDPp-MXepYxOKgOWvmnfgI1hXjNn_tjoKIELe-i2ihJZ_idoe2lJFEltxdHozk11leBvI5mkpmr5mpRZiAjlc4Lo-0V2DxUgcEAZRUcxQKPcUGzC5vqGLI-EUf1CATSJegD3b_kaZlSctl6MpQT3cHXk9Blx3IfZrxyta3eOKKvgQwWVVMBjpNRhK__Zm55E0o6VLdnfTZR2eYrwhitw31SrB0nQn7pLoCxKn3Y4dsZkWb78A-GVyx4UHE729g0JsL1duT_jeQWCsWRd1qEW7xi6iyUWuzHgJbbeZXq55eN60iINF3bDrSY72Pch8TJxDma78GUSwWa3mMwa1VimywAURjssaK5n-MzYfWEm990EbxXmDcqpOdUGLHzuLR3skpImb5UXWPBwopK4H_X7RL1LIaLPV-ndla1rECKRmRHxNU9uy2f59uQ2LQLxfYlKzjbywfbN9Gm_MxpqnAzXvAWBvr7MpU3NJKxffHf_iUVfraZMQiEdt0s_9G8nBv9ZEaH5UFGqF-QlLkyyaYRwWDtdQzYyQMe9OW121PGtZLxHhWmws5_bMzldQSZiEoggWm8pSLh03fa1igzEJVwcmokqzDmwHIA5Ek6CcMeCrfOjttziogFVQUGvQcYOi1n6Y9Wz-BpSTYwcB209xwmaTMxzoTBc3JqhkcYxcERQ3LsNShl_2w4zHiW7KB6y96nD1WNa1T_zY1MZ_0ck_EjVzzDpZLExMrpM-_Er-6drPu1VJf81e0pXChsQ7R0r5hCrkUSCPrqUWz6qTd5ytoBmnE0vXUn8mjT6yfg6ZMScq2dRLNKYW9XIi8jscyxcrA6i6-6T0H210V68cuqvb-Ktdii-nYRerW0hn15vWoaxDZDmVh0Js48KkE8IzjA53kK_V5q66Ua-wGCUk65VVQOxq864ADBV_At0BEU2_4J0VulazI6nyb5XtWZ4MyuDMPBNg8LkHao5VkajuTEoavikHMVizE_dRqKeTZdir1JSsQXm8xejkS5_06Cizq6amsBTAY4FdQlPT4SU12THIogRz0K_oy3V8dlc_Wsd0PJRVpcn_LA_-Z3CUCM40_tzI2hqIZNv84URWhgLBD2YTKwOgRY5pjtLo6bGu3dWEOAhQePQZ_3zP-BEcVU0TzqmI7TK15WYdtd6hb0aZukWtfz6kDwWA7bIzp3sVjslVwTO0L4C0AFcDPzggLSanlktxBd_orE3m5rqiI7BJhBQu1oCTk5jneRq0YJhQ1yp8h6JDfnjQ_Nzg1oOQfXBn7rq1xSeuA=`

* :calling::zork,call_2e9b3e253198419c9de7e01301f51a23
  > * command `"north"`

* :scroll::call_2e9b3e253198419c9de7e01301f51a23
  >      North-South Passage                                        Score: 44  Moves: 56
  >     North-South Passage
  >     This is a high north-south passage, which forks to the northeast.
  >
  >     >

* :green_circle::call_2e9b3e253198419c9de7e01301f51a23

* :thought_balloon::**Checking the northern path**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf53022eac8191b15be01ba1b6113c,gAAAAABq31MDK-8Dz0eoiJEqP6P7a4unCCMxi5sTikyvLjveU4c7EmqyaN4CpyleRavfr_wyo7JI_1aO5QIFROQT_kpdHXvHEialnOI8paGjWLV5sv9CHTnXOy9OZSAtI_FFE5c_FYocW-Op8Yp9hwyI4eaaXcpXSzbEbjIDqfP48GXY7yFrCKxYOjicY3WxBL0meg8eA3CH2l1k6_QhJkU5VTCEgoEhI5C0TwDyO8K0x0OyiARHD8vs2UkZi5jcW3WJc_o4r90XYJuMY2F6vsG7DCUp1MN8PyBO-CmwrNoTRaH8I9KvzAH4BbHyY65_P-qoAdu1p4MAe3pdU11m3uwrHUUOW6oVW1NMTyhU-XdxBncNx9e2Ll3S5OWhP-oH6d3bfDVHGyN5O18NBzAfImxuDoSteM4UlSHbX10XHe9IJ86Uy8E_kC66swQBbT1-5gdlyyvFClgqVhweDkGw0TkWFPf1C3wGla-7Kmv4fh3f0MwBl15hCOsf8M60r1KcbAG0-1eD9UnXEmHrFc4mugK2-JpwYiSCjC1SuhNK-nO8-9tS-XQjY8o5HlfOvDXnuCAAiDPH4ENY8GeQddwXFJklMP0Ze-Pbk2ANSUeIJ-TtKX0H06kz-lPkbaBk2D3zNNMvDb0MUFbA4HcuB8IJwLnX0P1seIIcuEY6DhDJC0xLRibCmVqwMRMwmZPBZ1yE7kQihzrOHHMFJfdhTj5Utm1az8vMr7mLz09HC2udAzFTcmG0DLFyVXOTE5WoJDPFaA_C-YlOtViapi1jbLCH2dDy-m7xyvrueW9FoNt6sDDU37ELonhytWbfKf520uSj1_zr3i6_yzdeJFuFXwJK3nXVScjUC9lBvL6KKb8rAQI2n9tIndioj4GFyQ5IUSuRfpZF5Bnjk0OBrDYpZh76tvzQtYda5IEY2yuIaiYQg2igmrm1iS5z5qCkxv_Dj2gfvaRAGsnWMJP9sOOok3C9fJYkH0irmUYhC_v8jOiZILU2k-PmXTOW_XT58Xb2UfG9j8EQ-pzeYic-V-xEDpoXcWjIrOPf53RzzeD4fHgxa4vRjcGUXGxoYhHdT4kKHCHIUnnTTyc3ptLs9i3j9XwMft8YV8iClbc4Bhud6R-nNqfYjtjH6KpjIFhLu2l27lttjTEwhi6MMppSdySQmgi5MdcCsUKanDmppHloR0X6SVDJna8IKibDPBQ8Gco44DfS52mRWSpcYIebOMnFv8oMo8WbI-DFrQrDGEAmtleFQY7IV3-7i7nmxd-Z7IkmHB-BoCp84USyZogdTbhdtJ_YM66j2uSEcW59X0ij9mWZcbCHVhCXFye7typrXG_AT7ev_LTHDA9mT2A0l8v7vc560jCnkE-_IeeeQN-sWZHneIgM8OTXMlQYgztt3tlzb-uSoOl6BFhabYJf63bLBJpobUKgY_NWdv4t_jZKS_G3zNFI73J0k9UY0Kjn0qNMuwmiC0KCTENjxrzC4_Dw0GdcV4_8OuVByA9iRwdIfLW4kB6nzehS5m2Gux1_1Ux080kfzG8rYanfuP3ZiQV8eOrIsJ-vJspWolIg5Tij3YXRo1-iVbv-RSnw64J5T94zDUZZ0SfmfZXgxtR1X1Dh3NlMGOqMwHV0GDzLtdDRraz8Sdc3af8jtvN4311gC8j-vx6EDz8xS37hWhFI`

* :calling::zork,call_b11770164e25435eb2e2782e314333bf
  > * command `"north"`

* :scroll::call_b11770164e25435eb2e2782e314333bf
  >      Chasm                                                      Score: 44  Moves: 57
  >     Chasm
  >     A chasm runs southwest to northeast and the path follows it. You are on the
  >     south side of the chasm, where a crack opens into a passage.
  >
  >     >

* :green_circle::call_b11770164e25435eb2e2782e314333bf

* :thought_balloon::**Inspecting the crack**

* :thought_balloon::**Pausing before the chasm**

* :thought_balloon::**Following the chasm northeast**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf530715388191b95f2562e56b298c,gAAAAABq31MQtegbLJ10qju-4Ce6QXhW81v30YAbMJC70viN1deC5_v2fZ2NqNu8WCagIprLCuRHBnsVZVUYLi9WpW1k8GNwSwJ7ygFld9ju8MZoi-DhCmJLBt96H5dQh12Thj0_7jw5yLfP03F7cMj8TwFrymWg0QSG5pfvj07wlWBTbagww7X6nCvxZH3KmEbUiAZpeTn98vVTCn-RPdzG4eKQdFSTVBE926-jvHQYmIIsaXX0gARIScdASyeNYvG_XM8aqSEe5L5xdt-5zO5J5VTlVAfFEFyw01oskEKOrTFaMT4Qeq-0pZ7eYGfvKDZqKDXDZrZe3jlBynLlhZIqSxyZGI0AuyZphGm_dZW2sQgXiPMwsiIXPWA6TiIYB8goAWLzkX8oEL9gG9Ytzv535vghZxx6ltGveXSodzPToY5wiIzaeED7YsA1jfsTXqTdHFnSqjya3XIk4OdIstlQhRuiPh64f4MqWU-7PyO1sGa9RxySTomAJfU5l2Jkg7Z783BxDXLByGzXB8n1uzFhpOPvIbR00j42wAlC8X6ov-q_kSjnTGSyKibMOL94dp3MMBVSj6ZYzhRbbgJ_-SEETsO73XXNEwTAOjSeRzNVqmKlEVQxBQS05DFW5d7JIUKkz1r9izaS26CW-6CTXueTBTxJNcb7Cg0R1g4X4pBWkk3_RcKx6Tx_vxOHscoj76kpGEuidzAaIqU849SanrzpQBE5VbHPFHX7QMq9YBaxKe5Eo3h_pSApPsLjgQtOM1E1MjLhV6NY-7XbcqUSgaw0uhHzD9Em7uUPYxgzGrZJqKABVtJAhfMwZ7wKXerC0lrXfh10d6jP8qSfd_vXFK_I8UnXjeMXCf8FQTNuou4YyIqRCxSxBTEL5-QB53M-sZOlznPqPKMYv6nIulaxovnSdvOVq67Vt_cpIqkM205LR75B0ynoiCjEPNNjwHU49bvm7-OyDqdI2WvSZJwdC8mhbxLohtKT2I-FzPtU-HuR07qRUARqWwSjFiCvvFQdvG8IhCG3fCaG0ruc78AcZuWVRmWrNjq_zYgaRvDy9C_x5qxjPFzECYkkgRQV9lMn2gYUGjUCouFDqJGr4mKt08JiOCwFaMt84VffT7GU3sK2zxNvgX1mGPwDcbcwzbz-WNQ2aWFTwHUaoBrgcZOkGoeR9s8YajodPBK6SORufwpKACUN8IaAQQ9ukwMY8Wh0tMYA6_Wlv7Oa9wlQAgJAz-BCJ78TSVFsz9UBWjDytte-RF4rC93pAW-RnzRYliKb1Xxn_0xyNFhSA8EjxpyyAw7LJaEXQb26-znjJ3bvNOUtOKThsd26i-cbyJuEl9rjrY0WaoF9N1K_vhftpfNks8AEqG-l03L2pFmn_m1UJ1Br61oxUn_683U_AQTqqAsw8jyEtuK2GiOWlI4lVOiL955xWGFPzeES6wTq2LCvw9H62znOMMGjrsW1c1v4jpCEpf1dcWBPh7MKhpcMKiRJt0_1_qBM5mfMlcn5LJTm2O_GvF374Dk-vI-v1iaONZTKcMuzj5tVtsGw-6iZVG_CDN7K6hmzOeWqr9IIygyjal6OHs7pydEmzWns9aaEKOZxih-J5Hq4YEw37QFYzvE8H38LG7bMfxLirho9AyqO4UxYTWkOa5bbl_krRxloFmfNHtrqxQ_V0aS_JSvyvxF36zb2nE_FtAHvz-3S0vbhZK45jrUHF2pk68U01lOQ9-bTh8exwD6Nax8kGGMC-ERljBNq3m3QqiHwcLESYHaHA5piEQ0nNvFN-8kTp_aTGg6DSkaRVLtf5bDhVV57XnxMIBeTMPv-8E2iRP55XAf1V648omepukCvRNwBsgQZHTHlUaN6kTTdwWLR1uefad2-HWQk-oiYirCvbjmjE0LiwqWA7GSIcBjQr44Ebnxos2FNP83parjs-lUYD1dYMOq72Mi-Scg9fGu7u2a4SGg-bfkZwzl0kedBz82obtN6wfsP7MFv1ESrBwB4cukkgc1_bw0bxYJ7JpsVUNn5p92REE88RPUgm4m8FIBHc0Fu3n8Vt15Mvv-9-xTj3LcG5fPp1N8RJyR-PipK0U5tn-hMOZJ-DN9PRGUlzfrd_IEmjMIc5lfGj67hm33sBIEKGIwKYp35tV40VPkhSaQa2U78VZTTTgQ-vBZDOnIZ3OMfKLlZi9v6TWUJ__m91Qm8MD2X40HYQDFXTcEM2LQ8PLMxTd6NimSsBPXTDG6om49Y2SmbUpoZb_hntrVWrqt7wlf7vrB6OJP4e7RNzlxkSd6vYECEwUUsgLPJzTm53XECeKoFBGDqfAJrx59NznCQdg9iBJZ9oCarYIeW3Pd9LVkadtaJAs53YieKmIktm21_9lGDSAYMZOSk3OcQHiHAjvTsFaYfPsN9fPHe40XFaQ9loD-3aEBcNBCx2ia8lVN70GQiEkorHr1pIwqiuGHW5GhxXsbrDe0QXaP1Tv1gbh1lHU5fr8Wid3_GrETlEdpf2XSPeYWhvxDvGDsh9xH40joYYmi4TQMTs3e5v9JoOOVkzCOvZTkM8z5cSC9wWLiCa0AkgadGWVCje-MRtkWp_IWR8usvoy67KlIAuqNTUC8f8H8H0we7ToWxpa2FPAJd1uK8Uqn59fFK9GMO45KnkxuWXIE4zdbbac9UMVVQYtPoitl-CgJpD_13VgO56COsnEipX_1atdNOqehvyH54aV47vx9GxYPqwoaeQ-zEn2bs9aSfc4Ktv3GWvHt7gWyzUn-M5XvTFtOfvZGj30V8lxMcPg3hxODmEzsjzJpnJ5yjWaHOR9sqKJA2_o6do8QNCHL7bzOEto2hDDa7S7mlpUxA3C-gwoZiWsklNkx7CgkXxM-DC4Bw5DCPKKU0tFQLTuOClRu2kNXmZ2AlCbiRTveOQw6474lW2vBDjmBZYGzBSuwOmeKpJKjiuhL2ZbdglExZFQLYB65UJSM7oYVyuX_vBz6e9hdegIARHVcarMeeZNq_oDvx266gpEIgtz90zS9afbxdBjtgpFuivm2_86UElMEwWW6a3s3NTay_RuIqjlXXF1AzaLeilc14VQYVR9LGa3QwzcDUDeM2lIb7hKgIaqSDNZnRUPZLN6zxI4-vwxuaxY4iiqmmdHBmuZhr-ByJENLsdUA5G79VZFAiVRwPhhXxD4M7JwGp-wlT1ZvQSPNxHG3j3jXENdW3cJ2Zk1T1Wbn_XzFFDduvhSaGWw-JmZD7b00rotU1Sb5OcYfb4tR_fghqLLLmBiUyKUQ_mWfSO5lXId9tLbjxv3IonHCSghS37KF2JmwbVbsvRcYtm4nv-I__mUVigtqT7G4KfW473zuDLPoaksQhL6dWQkuABMHDp61YCQ7Bd9OTfA8mn85nIERQkN-XZjay-LzydtDR4z8_DmHSFSTEgMT_LxF7PaQOGKtpfiqdXiUiKqNbEAX4q37qZA4UmGVDtH1oxp9yDI8yDmxXBry4BsANBqyoWjGEdl_L_dzdpB2K4jM718177AtZfMmIlqQkexL4adhueUCRwufsU2DN0AqfgCiGMpiDGiMPmnfNzLMcuFS1eByDY_Ufhyi7JBfFxuzv9gpks1vzwc-jejnm2kHm9va_QzPK15Kf-dPV4XAgOKB8BMG0Ry0TOJON_ebmD-Nu__SidI0FzfhEy44E4WO-9BAocwetXXamra306j-0bLrERvX_aEQ2si9txEHpWOiDlQfQlafo-ZDl4u6kOmMeR8MSkzzAqMPLbsOUYVfm4JStMi3dcwmDIpnAHUocUNpHoj3tylB1coW0T21kdz2HvL6-rGUs8CoDwTgM5UQ35Ib2VH0661p7QYGN5R-oWB2rCPn9tg540boxmy0rzefeWIGXXcvvJLaRA-Vr8_0fbV7AbxMhDlvKMhy_paP8TP5S7h_CrOZBgvRwqxeN4-bX1sxLa-sH_E8iBmcMmaF5o_5KqoSZ9VVdZl-QkR9L-nfXGWECBSqvYC60GnC0lzdKOLsYWYA0Ggx3E7pQGO1fWK5wld3UQBwFZa3LRTf_uKlTzZ1aZkkztbvfMVXKFVyuaEXaCBFHRZRDEhZvTD4NFVY6T1cGLVMcQWRO1FcX4Ue7DtfGIqOBdIcHoo7Qp9Tv7ll5cn4hAlHCvHdCwvrVHkV1HpkrddcnV8v_I-GMuMPfmfTSGGnAWZB6ludmOw0AJo97Bc6pQ64lcBKei4TxDWi3NKuiuWdv8ciZvZhkWw_9Oh72BxyZ2D7c4zKEiHtPYRjxm2GRtOXZaanL7cawp28F2yo-CrdPVSaNc5SdJZCRlqb7tzZEQbqTie1WIi_b1OOmG_r-9RshBrDWoLYU6FmhDRvZOVeDXLFKhhZD30JUKXjTeBrbkd9S9XixViD7IhrjAYkcZRW0GHYVqkgB4R3Jbtd6GhpI0znJdopOqRxLlrxKS3dL_R4g8GDEVwBz4qhw999yIUnT2r8qQ6PVhV8pvq14hdQEFanUHP67T-Q9xYMGR3t4XfaWB84uCZ6QSULpf5GaMbGOFmHOdXKKAkvXN9HnlEgJUa53l2beTfZhQW05HarD3cQPuOZhB5B6Cqj3aizNLF3KOjxlu-NhFNFD5Q0n5DjImdmhkUtnXHCT-Z1-GBN_kv7UkSQnngjqgnSgtQW0nTjfBEh3rxLSdbvr2fBtIHoQhuPTOZMOoTtDu69Dtbv-j04Ffh54nrn_700KjOA0okGKQfh4nfJnjrG8qZB27h9zn0S39DbC8gfh_y3JzodsyHi1wVROvUsMD1iCsei5DTKpJ5mO5-WaBeOiNQd2JEbvxG4B9pZnJtXxH9J2--DInYoB68D5oHP7vPisRlTz-Ao-NnLOyCEsGfdrdM8WDYWOUbV7OjOVmOxJLoQvm-OvBYOlQovkZ-7GrbS0UQebdUOZC4ePShIJx83FCLzrytL7jjik67Vy-pDjSfZuKjNaqrcnK6F2zRmhzN-C9AaJcBVWiCu8biQ9TBsbRbsQdWn4JiyWfbMTViHjct-vQnYYVMXUdOvu3Ohz2Mbui2mA6MNV9jeS1hgkLJ-CmnLViJfTXIlx0iI_QobXW1lvMzBWELqgCLwjh7LLe8fBDWt090ZDbICco95b9aZF9J4GpG245PR4KgoZBiSlCQo7kGFNjayjb55HIBKG5fmtJx840tWmBm_K7kkLjxVuv2Y8bi16KazNfe-WlMumaqht9KEZ11LSQucjvxwAbevTOw89XxC_LJ-1g2PTmexbnWM-ehL3x1A-ishMflTKdgg9Z3scqAY75lsy6U9n_79nn4vJiBgbDeof9tk30JC3-pkl6s4XJKhN1bQWnhX2Alr1gmG6kbOrH4doouaBwaMkHiCJ3XBJiX1_j4ifUA_tRER4qTKuVj7FQNeuf4NBBw7oxc_7jHXrG74kXdqHaWdlWpAme3JcJVThHCPKv5AnQkog2RNCbBtYGjtMFzYlGrrO-3eCqzMjtllySnVe5V0s7p9ZDKIq-9Lugl4jr9yyeRVFH8oB85n8xxYZy8K2kSqx12Ks2eeMhEPYCX5zOJ5b4EjwV23llzbg5QodgqdyjeTiUzf8iCu3ORYdhRimBKAh-XbXzSbiqGqPd-4uGCB2AMutJLIQCQHYMW3vUGR_apU5BJu1cztmlIkALNcKnOTnqQpRo8mLw7usa08DtRIzuXMRWwPILV1zx9Knr4P_OuugR-e5KvjraCWwMgl8Z6ly3OwvkjBTMSgRH4-4zjOiclZU-U2T27UJprrsiYQ24MOBEydOjuHwpmNWJ_7sApvDUWoRtcVDzJPxi_4dh3BWKLntSMu46v4y5McIU98-_tCJ6BFb3mGsjmA7LR8DMUOyNo5s_BBpN-pEUEgE3FSeS9PWnmOYdsfrngbuppTNPHJOZqVg5aP5clEL7cl8w-Xguet-2inOZcIajj5mW1u0Rmud8hpmy9hdhj0Xqe_7dAZQm8QqHbpCCI4N5vphVmyhRqajO1jusOJK4FgP10LnfI5Fbog9HouVFO3RkOdcHf2qiLHuhixhlaAA3wvY3DpkevmCngcqCkshClJaF4c8MDzKwprD2LFTCeFJkQdsPLbciUoPmUHzGhqL0hh_evRizP2HOq4Qv5iAfW7ENfTLoxDracB7swuFB9vkDmHnwqV_1FOHzs_fzkJ7BGWQKrwSxoX_wJuT5tPAvl37KHeQbG-7H8wmZpsac4T68tWLzXAJe0smCxnr9Cv2zJsqmJHZ1G-OJC6CvRlV2meuRMm39Ry0N7h-x8IdBXB895w_-D71JpJxV93nqIxJVLv962a9l2tE_oe04bFoRI9AdkIuP3HwBPLYwd2nfPTTgbquVA9zqFpwz6A4O7oQ07zme3W2BN1fPL19vCkJBAyfhRZjwbXmgfSlmGuyjzHhcxLNTgfHW3ECG_fSjoPxs3JTaBEvgsaNyuiN2eH9bxz5mMZMLSLDb5o-YVw71blzu1FZzligGvNgNXCKWAduw3hvGk92YvYIrTuHo2QTvHoLZRY-M63XLgj_OalLnCcbNRNAGcyz_7hl795aN-kmURdwyJ2drGLzmm7rTMcg82bv2PS8QtlTGM3s2XD9F_0evobQN6tfYeveaDDWlubtSc-J264oNjj7wCipIcx_XBmUvwq0H0ENmzpVuyOpLxvJ8vGqAXgDNc-u4an_xnME0QOHn9cbss-hfjuCPf_5XWR2VkoYqYjAN3Qd-13xEjyunA9F5pI89f4oaKyph3m4g_uclPTaEWIZbeAGq97yb1ZV4ertFGRtXbwZzhtaPCU1husqDFqP4bIMgg9p3Ag0L9iCsifj5NkhP3m9m-llVP6nNByP_kl56baf6QXQ91YUL9jkg6kw9Ct1O1KJL2Y-fYLaD84tqKvpLYTDiakRlLqNn85wttKizxOAJNU-ZzZpgnADcwJXH50yKeeNRBM=`

* :thought_balloon::**Trying south at crack**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf5310e2388191a1a5cbac8d2019de,gAAAAABq31MSytJfBIjIL85ssiKk_cJiCE0q_hmmjQl604JPkYQqxgUCUoI4K014tc2Y63710Y0dGKFqHd4f_920P5m3kg1T5tiHPePwU2CDdo7MKU0AV0ZXL5d_yZXHz19DDQULgm85IPLEmmkwLV-SBmvtQoprKHjaZee5644tHIqDVfsNzjvtiViTgtkbxIPc-Usa3t9hIypMnrAbs2C_37EHXP962lOcyq2YRc3p4iz3-saQlA8tfGloeh9VG2uDvv7yAi9RdNe_uWCU-ENLg7h_n21ZOef_MXk5tj-OwRBEHzJvTeEtYrumNzihgjf0fH0DQoIUcZZ6D8xJX9kTfu5ETqRWtIKoa6L0oq3A1-UlBr6shWItUM7U_Dxs1U4ux4SNd3gN4rgXgED-ytm-5WUtz5yAarDZXHLYI5Bf2t9ioD1ro2CtP79M5dn1OzDsZ-0VZLohRYVbXaNo7FuxC1Pv2yTJcXpNfmF8VEJWoIRIYf8SYa84v0rrtVcq5JifK54a9rfj2EOyBxXkzavV8qLpBBnPQfq1a8dKiAi1BPL4IPsozSzWISVqeYVhzoX8h5Uxf8k2r-sPmWGpgdpNk0SOu5XJlgaV2D7Yr6LyGCFs15Ue3ardLlj-cR5y3OUnFHglpN1_oIJJ0HCouErfAiYla0wnnvsWjmJqHwt-1mZ1g1Guuv8CwdKYT_qLPd0HZHd4syegMcDcNcLm85x59Dr-fL7hpymI9OZghtm_PEza_T29mGSgxINVopfuwS4g5tXmASIXFKe6evlZr7M0qGD4IxECM18OkmebQnQCRjAjdEuX0wnq-lqgGSLezdUs64Fgp760ib9DA0L-5Ec81Gxla_ylAx0Xq2zOZUgDf9vbgcSaC2_oh_18kvN4UPyI1-EeMwce1XetjYgbsp-T34_vZC48AVasmF7ACjnRk6adjALBY-h4hpDg2UiHz61S0_SB0SIoX81so3vU7KHBMNG_17Y7jQeIU9mb0PB_WbLtr3NS9FJoGU1nEeAP3N9RTlBlDTt0AwjYOxub5Uun58T17fDqGiIq3GMb0i8bN_n637ehECQjcGL-coQ1jDW3FlUEul5My9HrSvyV81__dvE23bQqJKEU6h8eT5ZlDbJRXojgC752f86jGx4QH66pxxnPXXiDTahtPVlRZgovolcq_uHorT4fxK0RoLDUsp7D2I4sc_pRX51CCPILI8JU11NHiYrX9cMWHTOTH_l7wu29kvObhhRdzHDbyNHhIZnxsTPGFQhQL0gnNJIXddFo8YRHyM66h1zonj3O3GFv0DBtocFJEUL3Yb1YCqY90Nc3aMUQL4MUwBEdn4uLmB307dZl_jzCbiSg7spwBYbGF6lAwM1EGVcUn_FSGP3eEV1EZoI_zzcIBr85gy2j930ngZtWFgDCCLaWo0HvWszCLSVl9XVGKNN3Z4lWCPPE_Swm-74RBfJ0h2Rj8Du8f3-Tt3UQ0ZX0KsdyjJKAKHrLH2eYs0NWu1LB94uIlDxvdbGR4wggZm_E3LBSBrwt6mGmkK0Ye4Rdi8bJjakQuMUjwS_Wrb3bFyfJcPu9VIpIcEY6drK2b6XMFRo_Z3UR85k02VPzl4vejGGakprZ7a61XGOLXBaVqdrYxawAgKKSqjZtFxFteLO-TxJbbHvVxTG1p_rvC_9Obsz8-oYIqaqJS8ArPZbxfald2cd7L-XSWA9qWUJ04vTZqw6FTjYgkIMyhv3FF1KIt63uBTxXKpiSoJuaLVnPBtzZo7pWcCNfZBU68piaSGsuK-SA5sTFLr9kZQ-ov84n1laZRjSgh40P9xBukrLHUIrNFkHqmcQvONoXj6n-rFEiiEf3GN9Bd6K8QlOKDOrL`

* :calling::zork,call_e5c05fcad4564fa78078eb97614bec72
  > * command `"south"`

* :scroll::call_e5c05fcad4564fa78078eb97614bec72
  >      North-South Passage                                        Score: 44  Moves: 58
  >     North-South Passage
  >
  >     >

* :green_circle::call_e5c05fcad4564fa78078eb97614bec72

* :thought_balloon::**Heading northeast at fork**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf5316359881918ce383508f825e86,gAAAAABq31MY8YhZirtf7_0sievIXqu2cVk_B3QIJBwE2k-t6-aNdmIZm58q48LwwRCPIFbWheiC86yF44X_izF-i7Bdoucv9w390eX6MVACU6ZZZyJG6bFWwZ4AInRzO8WGQbctE1KxkJrwjIsybr57kNSQKuCGy5TU_O6jXVJ_I8pYs2SMf7r0dMJzHsUcogDgEG5C7uAMyOIhWpusHlTd4QOcGiNQHMEUoBaK9g4uiu8Dhw2fruS7zx-FumxP6_YBTaXIhdf6ZYuMafYH_92s76GZFqweUP0ikYPGFZDbO4LMmLS5osY9WkXy6Ga4D1i1uE6-SFHMA3pmWGZVIHhPzP2Z_kA7QOnSdbTdNdyGeMO_Q-AtC6uZYYuor2T7n-Lxds236SHnomadU-lDBSXJXnOZYxrgebY0bbdhn3jV6-7RDOQH14VHszRQdJtKx7DDxy6uCjoj67UsfpRgnyvT85uwCTCcl81MjFapFZwieLIKXm_WVoHQXUohBn1nVDoHYcZ5ugOfMXxDCQuNeNzaAXRaCgsKyxkfFMo1fysbdZ2-IsbWN9AuC9_satCJryPcYFUgG-inMQRCmNWWm0euTL-DEmyW3uQSIrH9PzE6RJMisVGUKll823voYg18R2Jd_wFSE6hE2F8ofbrvHs2nfsmIcMRnlo6sBdr0kgMh_YKyvptI1l0nEnqc1phbObr8R_AWuMGt8xNBElkAM3vLsOo5hi1XA_Od7R7_w-K1XmEZPu_zVj3sLTJz0wCpbsR8M8To1s3BD2UmP_s1Fu2anDED3Oc23ezf-GyF_qeNQzWoN5U27UNtpd3xyYoDcCWsoqOUDI0rmibjyMmRXVq8ZK4Fsq6cE_s19As2at0q3wr0Fs6GbuxUoV3uDjekKdfsuLGSxfhBpo3gxv4v1QUJRgvarbcZzXE0W-EJM4SucQQBuSHR2W8WimnGgaS6tjtrE_aMAPsgdLUf_-XnnAxOmflUdxj21S7AqZ-x2ot0VuH6oWGnO7ADajz4zbbZ2qq5VEL5zL8syGQ2_q_j4fQQIm-gAvpVbdEFUfZbr6tzTnFGA0GgWaEBU3dSBj97u16Ja92sjLD_8QOj_cUFU6vhDW9X-TFh4HrSPRKqocyriiZiFIpRdbnoE8Y3uFlu6-c8pDEP-TMeDhwvtu4mvXIWo8rOJKp_10l0dDwAapSq-KrOdbITwHh77wQDngrn89g1YszdLy7cTaK63RRroXRPD-hoOG7Z8_aIKhVhCe7Y43psp-afzjg1bpSUL73mSysqbdXp5ZJPwMAJ2dT-iFc3-sXHA0tdEZ7oXfubaSTAJqgXjswoSIsaaVeK588-IjNoswUVNtLnX7bBcwiHlNJA4khoeWM3IwkfIAwJkzOQS-bdOvwXMydpZtHg1L6H5k5MTwpkaeohNROLOsNqeDB_2--BEWQfRpgVhUad-H125gsov0YhVPF3xg2x3uOq709bwOvLjuxPdUNTnuvQkVmmEClTJBcke8e18exL00avaJStqWoaRaK8YhxAu5F1GZjPkY0tghTLMR0sVVGT2-jOE5uxh4kljuqOeICHovfSoc5EGDGyNDe0oWC_-wA7qrpH6EJpHvQMAnrg24LDbBMkpOXsdw9i8O5aB9PQc8HB1kianGYi3sk3rQCvTMgg2dBD-A1q2Geknn-m5fj0dWYItROHPNDSZOfbLo_NULndYdroeRy8CQ8ebVPp0-s_QWii1aTT01h4FFlWO1wGSWYlv25SmMDv3yUMb-0292soXe_veFePn3Sm5NFWMvjQX4opvsf4LqE6z0SY41zr4MQFNqretJ7OTlZRRAKU1xXCqmAtbaJsjaTFvrEOgw6JZgyOhtb3Jm3wzalg2MP0QUBbtjSA0QQfHg==`

* :calling::zork,call_ed9dd21001b04690976ac604322fe1de
  > * command `"northeast"`

* :scroll::call_ed9dd21001b04690976ac604322fe1de
  >      Deep Canyon                                                Score: 44  Moves: 59
  >     Deep Canyon
  >     You are on the south edge of a deep canyon. Passages lead off to the east,
  >     northwest and southwest. A stairway leads down. You can hear the sound of
  >     flowing water from below.
  >
  >     >

* :green_circle::call_ed9dd21001b04690976ac604322fe1de

* :thought_balloon::**Heading east toward water**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf531b40e48191b70903475b9d43b0,gAAAAABq31MepQz1NyzbYPWT2oe-HNJ5p4iwSmQ3c728iKXdVDai-7o1mivpR3EIq-J1k1I52oP8woMW8eQvKHQu30Phg0ztL28sm9-Tcukoqha659oRPVsa-0kd39WV_yFdb4lN0uV_SflPsc83Jys28zO9G23QeLGUF407BiFMNcvMF3usSI0_StWqLalPjLEbeo7l2rDY-Czfn9GA9pDeCHlAx8lmuhzATAUujU5xWM9aVj4g9Edbsag3XtRKrVJsETUvPJbVvhEyI3NX0pNLsPVT97y1wC1AnmsjkjALnPwCgDQncK5GIli015DnzatNR5NHRKEJXHcwRFgq0sn42Vn9AJCILEH-HwOq1-7kz9LPvBPoWQuzllIGifqFmZRwJVlIlq2u5VHNcEYZ0wFMeYrPeWS4Qw3uNJCi2R9mBCbQo1PnD6JNjIJ8S_nb6jkJFPhu4MhHYq_Yu_PW6dbjxM4K16Gpfi4k79aB7SXcCyGenUZxLEDKrLBuot30AQsI0nDCbTJFgEs27fAmZqvgeVzjr8Xewky1JQW168qmCH2pA5ODYY1K1t2b9-Quegcgb9xJ13B1n8VM5uJKhB6hU5obN3ZQnLhtlzilQxK3yD0RGdaedrgq1VfFYsnl57qjkxAH4Rrd36CD1lTvHjYes1VrvJbyUOnbfNvW9KR1Jyfi1RYOrdEagLMAD2Di12N8-X2EOPxHnxb_okyv5plb39rcA0beoibG6BYtga6TYVoH6YSFU7vliJJL8-QrtNy3PwkrWM5Gu2DqBxGjEIwVasBtKXso_FINM3cP9g6w2N7yZSvpAbDK8UzEBUoEEqZEcXEt2MXHvkwcM6buEf_5vmnIdcXRTsyP3jNZ1GmAhB6PON-MWYQEKc09PTVVTeHU4aE3-_bvF_X-oN-ka6e8wV3Kig_iMmf8ilnvKTeM6ChDm5BTu5wDyMO_FAmxMdWF8V8TvG3PZCNGuFfE7vdbUOu13rzw08PyDCBLASHGc6QAPPMCUSmgMXFHW8FYbisI2Vh9KboqGN8xi0ytj24k4hfP7FNsBWgM4Kk4kBdE1KTlhuDT_BIffeTi-sny7RvzLH5tbyUEj6oNJZt-R8yGD0hTMDalqUlyVcO1ZJBp4_EEohciWfEIUyJQ6e-vjQnGNxGkq2-rvYWS7pgLpCMnAyiWTzfZ3Qh7G_0uZneg6qyHMFTnc85nTEP7gFOATxrskk9LjDRsCTO-vYRviNlnltNofTtupmsfHiy1LRXh2iQUosMCNP7zKErOpjc7tjYnJ71PEoR_KvY_QH37NioyPLVVV0l-wD8KXnqBBkGqGvGkic8ogkxXYLZoa-qpEsRm0TgvUyYkGAyqpILqtJtMKWfgQsIFwlkHV-QM_sA9RELa1Yx5XFhZk_BG9_V0paCHlV_9CAqZeB7p0N9RoBw8-PrJrxVASUKcarqFHlPm3PI52HXNC6YDVDUOEt0RqQcQ9R90Tdle6Bx63pTpIs7ZjKeiULD1Q8452j0VIkiJixKxwJqe7dEVJ8KFW4gsWHvqdKmpkaV9tT-zQEWmQbD52Shx7R1xSu7i3D9W72rKPKq97o6B_gDnRyfBUgOGOpxcSFdBlyk8iFU4SNsPDO4asYkCP7o2fcgaAKn3cJutVYT98C3Cx4xGBIxHf-upIbEMBxWqSReZe6IYAG2W0vp45SovYsjDqruJulVwsIZeJHYPujTO-iE7QIsbXmgniqcsYaUzdYERC02qbfJfiRskJV9Onl5Artm1840WSBdckeEDnJpRSb_AMz4C-QXS1sVyi9KKV2ISYshH9H-Z3Xv_BWKWDaZ_OEMjeFdwboiWlwIxOv4HJO3H3NblC4q-eG5TJP8_GVRN`

* :calling::zork,call_3c05eff82932429f8b981cc9228d0f1a
  > * command `"east"`

* :scroll::call_3c05eff82932429f8b981cc9228d0f1a
  >      Dam                                                        Score: 44  Moves: 60
  >     Dam
  >     You are standing on the top of the Flood Control Dam #3, which was quite a
  >     tourist attraction in times far distant. There are paths to the north, south,
  >     and west, and a scramble down.
  >     The sluice gates on the dam are closed. Behind the dam, there can be seen a wide
  >     reservoir. Water is pouring over the top of the now abandoned dam.
  >     There is a control panel here, on which a large metal bolt is mounted. Directly
  >     above the bolt is a small green plastic bubble.
  >
  >     >

* :green_circle::call_3c05eff82932429f8b981cc9228d0f1a

* :thought_balloon::**Checking the control panel**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf5326b3308191a3d5e939d75296fc,gAAAAABq31ModSeF1SyzRwRhQP0tiZhboBhIEB0gL8qlqdMrIJs-CGK6O3Pi4boJCTcRVzqAF63gJ2GWLcx94ESvtnX663WxEjHSyP9fCftdfZvXiVJq1QTEjKkPXEaBQY5uFGGYHWyG0BScnyYrnDYorp1IaQmSSFpQdrGLVB4VuBgyosRBz88nNw_XEo19Jn79HSFZClul17yD5wVPSFEgb_NuIs5dm5vmCmfbYj9mKoATSYYupbBD-lX6YTH4DGb2BD8bSHUpP4gb_cgW9jGrLUgFsNqMlfB-LA5LcPkxOA14ObTSDYxVVJz-OPvsb13d2KxyMiS_MNC3WA7GxVcqEAWb0hO8PYLMoawtvNgBSdGNoFjWPRkddUPMlMwpKFkDnhqJJf2CKIpaCzUt4eYWBTq9jE9o-d8Qg9qYjVrCzJ8OEKODX2tS-erZJImBC4swmApLreIRUhDB-C1yDcBDW1aXb3KLzK-VxRiHIcgf5qG-4_GJIQmgKFkpqLfMRxZCbV8CCziUojM2SJo-kdnoWFpZrmIA8lCiX0Eh5zYOkq6Ucx5_rlT73MdU4hcNPgzIHfrXWNhAnAo6w6oT2biQ4F74SBGWQT8iAN9HwT_qMJACSu9yItq3EuXvjvCrIVUtIVeSXtgZY9zebs3UuvRrfVK_83D6W8EDjb0S4Jqj3Mqkg5qU4YA4x-6brweMFVIrJNTUVYQYplKTmDoBv-mHBZKh1_r3T3DWVuCVmk_jOxasIUCj1Regko8y6HBx5BC1ky9LZ2MXmHYWK39CPXqktpbELdy5N9fvE6LM8cqsdK036HN_3zamhn7fozk-YTAeeLTTQxAOlfSaJTDwQe2W-MTxp3l8EPMGGLpfStt3dysoNcw5FsdiOy0QHR0huyp8r-wQ4EO-wo1ssEhARm9bJXR0wAXpHqY8RN-cCfqBwTYdGZOgCOjpPZ0tdfZX450E3Io9_80Zl5X5wnBsW8BUdxBRTQjXgg4QnhHAql1p6RJhpZ-cO37e2ZqdGlxMeYb41GLPta6JetX2JHldl1LGVzkNhPXQYXahWsI8TmQgHR6Qs_ZoKI5QIZcm-xVm5b-Vz2XGKzR7hbUtxCWkpvDy7Jw26mSP5zrU3sBd0GSip_mBJpP570h_C9dOz9A_kPMH_WxeiZWbTJJlWxoLhOxWjaOwdE7wHlwZAcRS37ey2QjIkUubBdM6EonzGWk7lb0s620rignIetT3PoM4pKiDBrnJIoBtXlaFDxgwdwHda9lh_wVvNqLxErqBbf4AueA1Ijw4UZydjwtwtP3NeUIgBJ5crKNi3WJR-zygznJHpVpm9pDlIki4vW9deV7mKWlilZJcWWQMAwEU0RkrD-FQu4_ifvLZag3rMXN_edET3uXKKbk0X3NDy4ZYWNtfS1RzW-p2uFVTy88Dvz1qGHeEejM5X2Y--TW7jJWs9XE6B2HJAgAu9cLhOBQwBQ3RXLSjxV4CnQ3QpGebGxAQxp6vqqOG15JtZ7MJCgc9XuhoSCdMeazm7K66DAFe8kI7z58hBUUWEAJCr9W4_O2WWfbictiN5nKJZLfQg9OqADExrC3y0o05LevDMhmnDaIJRUKHoWqmfPF39zHqTTTR5VgzysfTqRA1raBGvvnHPR8Qhwji8qE5E5Hw6956HCLreA97PwCplx5Lx6FHSAsZ3-h2jIeOLg0ISoTB90UoWwQaujhPv_IY6ylPLghL8OpZg65tly1ftuPU42s-Nu2XrZtHAaHS0HBCXGNhXQwjcwzEYPnRp32YCBa9xO76x30b9b2GGhkNUAtDUy_63C-R5-ba06Wbr3bm5cNVVs238TnXzpxMDgV9D9-pBwuhQ9aC6ENgnZTh7x0k0Irh7y8Uita96I_clSsDBrnxry7h2yPyhV6ydrK1u07YZcEhiu5kGMfTw3_GRXuNfaID-QPqMGJBNr0aBnRy4lBsQblGga103yCNwMHbjiQfcK6YvehoJijbK2ijIemhiM0Y_HBRFUTFMS4MM3NeDeK405nsBfUpEvQTI3M38mY6aHBqqcM1voR7pLrL3m5xSWu2IM8CWUPNtGJSlEPOtpsC3qlv8vS2yiHCjnwRZoad74AV0NLqNIeGa01xyR6CqL34O4D88G2qWGG_REuwqRkh-0TCthDtWAQx8MNYI8deKyHJLtAXzkONwE7aUo4HaMgqSUsQBQoOS80NDMwk5d-A8lAs0KNAB-Om_h4KL4fI7buNUjjDQp5b4Pt1RqR5zFrZqJcjvGbQzjoILr8MhMuKrYZrcU-MavAxy0JhzzHz7QO6a7awSxVkpjNhcKS3`

* :calling::zork,call_f8be543645f445beaf204e3d6f9c9f53
  > * command `"examine panel"`

* :scroll::call_f8be543645f445beaf204e3d6f9c9f53
  >      Dam                                                        Score: 44  Moves: 61
  >     There's nothing special about the control panel.
  >
  >     >

* :green_circle::call_f8be543645f445beaf204e3d6f9c9f53

* :thought_balloon::**Exploring north area**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf532bde308191a9de60586805d8b6,gAAAAABq31MudOAhlHz9tRGo9HQZiZgH91CTpvK6HBJ0A623Nt0gSdJUEh66sgIErbKlcQH3YGy2eVpgfrY9HoTnsZQqxClw7tWqhBXvwMhUXtLlLJ-_ovfaZmFOhM5rHhAt3OI31aTjePvvropr7pdjlkY8KuXzETq0guU-ir9WToJgltaVN6kASpe3RJpRdRgrguTroPJXlkGAZ8RxQ80D9Sa6Obkir3qY1lVsu_wUSIZ7gjoFiE78eeQVRHhoUBXxDSfFoMhlg1FDHxHO-HXtKyYLE_pPkv-1IBfxaKnGeczOsoNjoMsKqdQ540_DGMzrr79qaRMGgXfgRxT8WLgE4C5Oi6PBgakVLQW0ycHe8FKGM4g5sSJhOoud6AK_4z_iS1BB0ie8cFE7x9zb3B4VCxV9JYdmx8B5tJOxImxtHHzmwS6m3noDrUmNWHaC-NKfO5GtBS5YEIa8rpCqJ_RSmc_4EJPuHYOoAQBYuEIxJFoBUveC-VHO-fqFYQbuv5YcD1_uwvgDXAS1pu1Ss3wXumY3EwLjCmiMBJAZl7P-028JkX3x4KSchMBOZmYIOow9Vbbe-AfrCMiZZH7aJwgUa5wzZJ_5H5wa5hBuNpyOmHuIISzgldwlunr9MbM5VLkAZmzsq17vEgCPumtpzk6yvhfeziiqv66jo99iQVfwfk2U0yNLYMNu7KGTFkZhwFonBsk6gk67MwTzbcWWVFkcUCMoNOBYCTHuzp4yzfeKgiOeUtfDgHAz0xhTtfJJLBmKbraxW2enbboUs6QMof6UoZaNgNcLIAzxi1LQ-cTSqRl47sZKzCPrH99QacEBqKZl876kkuXE5AV4AItWSnqgHsVM_IPVtVQH-ixPE03v7P6h3RpVIMGSecWLPYTRE_1zQBmDR004sqLXlIeVyMuJ2dnGsTYksn9hOS1YIlq-ibcKVsW3EG5uT381x0bEjBOeqGI9uQxpC0gZeL_SpRDtsMOLJlxINZ4cPuQjlJSa-ZlY3XldezPo1n8UcOgpD1Gvhtn75FzPZIg-W_Fq94JZc-SBwkYNFsZgR41UY92f8VMI_0re-jk9G98Y1u2c43H3fXlxKOJD77EiAJqDjLWfEUK_SgNZV1ydIZ7K6di76iE3D5lD_TXQ3769ZStt-C5_fV3WSbTdVeBynOcmDARK31Nab1f6CdzFSKQdWttBjkfTN9BytJd-YdJlrrdJfLJmLptUuvfqsoE77L37Tomk561Ty_09AHQ3vWbU1r1r9ce_9cr44Vt1nNkz5spIZHg0USdjtgauGM12Nz7jPkcR0LSpztDEjek4MPSNLMBxS2kmLpdy1NaJJkCTgbZQHINClseXOyIlGw96MBqwhXPwZotQ5LtXZXIcCGGauWCE24FxUplvlDUmbtNsbr_xj65ks8mDCg966p2eV20X0JiDBuTu8b5FWWZGr_5Was11wpWTekrv2gQ-Fo-dxCJ-S8Afo7Op9SIpDQoD-dpAOEAB_uQPB3oTE_Gyopo5k20Mf9Uk73b6JSiMmqhAzSxEy-ATFNASJ0KGAhz8vC2Z3zf6jASC0e1nJCWcRFtcXMLSCE6GTlietDzRY4yb6wWzmeqHmI4KByigTU50C6MAI87CmaPF0UX1kqYVQTdpJEFTbm1oS7c1_0jZ4oGKNzPE82p6dd-524gosk326_LlycB-Qa7WR3BgDxeJDZI9An8WKR69LddjlopkY-PjHIxS8PIgW8KUm9JSRG8gMxAtslRC4G1fcDLsTxGFzdshz8-4MUVuxTIXNrUAfXetqvTGolR-r6eqvXQEoBqNR5hBlrdLA4D63F5CYDS9ziWU-Z_a2y2bxtYPH3QurhSLHO9OrjA6lhO4AGL4oLyLfMUQrcp4nax1ggI5cJsHvZQzH5MLwe2zK-4gX4lcg0Cy0mNlbHAhkFw1Ac3DAuMEynZwrwqUMtEgisuR4CrDOXiaMBMJ6xcBmN-4heE=`

* :calling::zork,call_0a888bc5c5d843ba804f235a61a0d26b
  > * command `"north"`

* :scroll::call_0a888bc5c5d843ba804f235a61a0d26b
  >      Dam Lobby                                                  Score: 44  Moves: 62
  >     Dam Lobby
  >     This room appears to have been the waiting room for groups touring the dam.
  >     There are open doorways here to the north and east marked "Private", and there
  >     is a path leading south over the top of the dam.
  >     Some guidebooks entitled "Flood Control Dam #3" are on the reception desk.
  >     There is a matchbook whose cover says "Visit Beautiful FCD#3" here.
  >
  >     >

* :green_circle::call_0a888bc5c5d843ba804f235a61a0d26b

* :thought_balloon::**Taking the matchbook**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf5331d49c819183d0883e1ac8ae71,gAAAAABq31MzpZo4lZx7OSC-rRUOMqCqPDvhAsbQYERZ-PggVK5mcIHP_t9HVQjbh3kiEdvXz8LmuRHA7yDyYWRVDg3lvoxASl4D_EGTW_yK1hhoLHFkfytxwEGpFWypqPqevsmXym-cIHQPcXayjg17bkrRs9Vv9QOLuY_Iupp7SxqfzTX6a_1fTUG9GvuIR96MRp49l6rK8kOVR05zrc42EC0n5gJydbp40dE16B7Pb_9ODoraxT-J30_7NoAbcPBEmXOX3ZkhN9fQB4FRiN7D7ZQIJUcw6hmSte1Qljw_Qv0f6zZz2-SGox4807qfU2znuJn7V3NuAcrVFlIcfoEIsmlpaTJKrWcinc--9g47idaz0sIvwh_TdExgLjaZvo_evpQJui5J1iyZScMxOEaCAYzX4eQgPcNQDjc6kJjIQImvdMzWDaYyxwt9ZArWFyPLUS8Wae-Ga9ZvdPHeMRELkayRVyJgroNDTYxTF-6ZUMoUetRBmJQ2BNZ-rOBzKxg6TZLUr2VPN5Oly1EokstboXwmnHNtwBLWu2zePfVqfIHglrrBJkGWWQRm-QpUSBvLnrK66hmMujmuyA_E9qyT8bbXWjlWTdNSTcTwgMpu3iorJtHRZUdgxprLYeSoMTQaePMfvzo8HWuiMfD4KMXAKphr6NqbIEMOroH-39b0dvrr7ZZUt-9aDDwHTtb2pcZ9grUodbjocXgOq-qaZbVMNMiXP-SGdPXRjKpyoaoJRIYhVPIySVa_j_5yFj2odImIJFF0NhUlL5zLSit7-BIhdNtkp_GEnTye9zdoV83-JEjTiCmFgQgeLcXugRMPD4zbkfpW-Pb82nXKm0Bym1SXoJbIrZbdsMfdAfHmz240QUX16daJuqxkff31EyRyi4zncLpgGR71tZRI2V0Y-KLKHS-IN8JaLNjlMW9zVL_7Hi9nC2_ep5zxy0MYCr-wWG1Z__-Jaar9sxfZjKLVtzNTvXn7AvrxGijqU7vyYbQZnGb2Ab6M2DxGtfwOs--ThPFnRKyaLpet8DX5jcMx-Aw9U8i6moujGGmo2A8TfNmvfI0xRk3LCoPcTJFOV2kUffHHOeyWuIMP0OvJDDN1trbA9CLnaLNcom1AYiy7Ia-J8_iqLVSxdM8SNfk_JUEPb-A6_i4kivalZ0eJTgVW0KhIDYnGGGW33p_kIDzuCdxMXJWLf2JSCMgrYctRqmrLl4WG-jDT_ZdNoCCDpPhNmulJD4DeLO55g_L_EOQDRHOvuHRHhvv6NhjM8mQQw3TrBHLbJN2sRcnH_G0cDiHr4CVT1aSoqspy2rGosmO2iS1JuesHUdz_p8DSPFW_Ia7NH_rnDMDFSjr5wmTYquVgV-zOUB7e23OO6CtbGImQRGPA5mFyfyNEHb1eskWiENAJ8FbrjsHU3Il3FZuypwGg5AVIFklYGwuhFWKEsj6M6nJIqzlFw1YDhXdO4xSe8EmIfTQvEYXYSXJBGyO-ayBIaGNTsMAb6azMTer6yPN40FNm8Q_4KNVlbH2bPw8evXJS0wrM_4FZ4FFARhJshnNLTpcuh83-LJTjY7LkBep5DZjEZSIvo6uULHw9UxJZs3oGp0gg0akR6nANaglA5MlqkOEGg8DmHWaYmIbAb-mKRaOzBWw3zGsH5Bg01g_TypPmski1n41AEYIKwOu8_FHM9pInr7P6jArrff2WgeY_4L-moJSs-ux0IPTCqxDFD-WU2rFQx9J4wXDbkANE6PRzRauHfkj-L-U3L49b1dFcw4PG1C354rF1uQ9DQPrU73NwM5VyA2jV4WeJ3gxlj2morg1Ze6VQmY9U29kTLjeSn53FbJ7r4DPPRsFgO7Iw1jAyuPMz0J-KXCeuch69mrScgHao0YggI0WmjA==`

* :calling::zork,call_3667d3bd27784cdaa3485920ac63d09e
  > * command `"take matchbook"`

* :scroll::call_3667d3bd27784cdaa3485920ac63d09e
  >      Dam Lobby                                                  Score: 44  Moves: 63
  >     Taken.
  >
  >     >

* :green_circle::call_3667d3bd27784cdaa3485920ac63d09e

* :thought_balloon::**Taking a guidebook**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf5337e7c48191b92f16952a5b4171,gAAAAABq31M6tCX9pCK-zoVNICm0iMI3bn2InmSSvUf5s3rF0aomIVT09dHedXVhkEdATmb-BsVQmE5lfY-POfBGgf7CcRW52_ZfqZrE5uNlGn7rqeLEyMDKCdthgtpkFZFp_5bLTVYmZ4DaaSfIIYIN22ReeureTxRx7VtVzu1o5_VMNKk7isLGTZahGkbHKQFsxI2dit7UTcmLnvCBx5Rpgx6xRv7tDiAQTvfVNeOhsBv3qbBHxYAyBnM5rNp_K9p1KIwYq5xRAkNhtpLL2lM4-lSf8RMQua3-LcR2PAfxJCUu2zAWoBzK2ZCZ8hW4mXWhygA_OIDCjxcn_GbJcd1K_DcGoHkY1oyML6lXsli1HpAkXzGvLbVvJ24RURM2KL_KdP-VnzD_xCyorUw9M8fi7avKBsoZl7ETW1vQ0pzlfOB3oH1GMb4XILAsiyuojy3OmXIedIQZKCscAYtEoxcEzzhyYsiRdfvwI1Ne_vAi4ZfdOEPXd7ZIwCmF-hAhYYKZkCYKE0sDaLE1mGv2X4EntU9ZNCuGAcVr4IPkkJfyLTiLfEX6m8Fu9XCznkX9JJYkoT4ofzChJPHNfajPvPDz-rhr0FUo7pdTZITJyjFnSLLysKyJcko0_Vuq0-IT1Ff_E-4j9HAShdtp_m9XkP8d4rghG1TK7sDl6FE9-ljAT4g_PQoIKI9J5f2uJ3dsNG0gaqn7FohZzLkfP1az158OcS5Cgr7WoV3-7s3Eb5MMt5y-IM_HgDFAK1kElsMcveIoGEYSK6aVRb41t4nnek9A6G6KlAWTLtyzeL0rDlhbgIt1rM0SuWIPaaa5CFiJ1ybkAkhVq7MQ49KolxCeXu7djvFzhX2t4bGojZ1v54tLOXx8A9RT_WMxaswXRmb7GX6SbAcjxv9lYg5BHqBtmasge8qEBd58jJ-9UPGXMQh0zR3g4F4DH0hqBL3HlTh3QMh1WyXtJE8INF3ux0ASkvcuiLFvRwdgNJghY8Kua0O-oiBEmD_iqtZrfYG9uMHoKnRrENLZkWiUuRBYLNNa5nHnDAERGvGzKIbo2M-dA3RPtUqaKlHIZ0UV3B40QEwscWlMJRYzRn807jFpHpt2hYSHgCLMn5FskwhH6mg_wTVF4n7OCXCKZP6xJXotgn7v0iUVf0dnwbvx9PlyQL7YHGwoccOh2i9iT_UtSR_PYaKDFAHA9YSG3Mx8i18KdxtQ7GWf5DByOdkb-5WKFr8ogmhrgo2t6jVmnmMIos47EpF2BnuhKtcGBWxbA9oLpK92XBmArKwGrGxr9Ro7UiBMFztz_PKdFz57czqbG5TN7-QteMCf7SA9g6JrAlYUr0q2EpgXmuxsgkUWfbjbV1pGGBUYTERvqjsl4_dLL5WY0x4QIidVNKenQvTmgiux2_Vdcsvsw6jssUFgxrB8USY_JaGntrXfXo6dFcpRgh5dV0BStGUjKpQbAQoPXrZf9vNg_dHftfPJpEpoWxXRfC7ueyplVa5F1nyuCobWx3W2GDLD_Oj_0D94HkQc5fQ_G7ICobehxIga406Pz9FcYD6MPrs1hEvwLWrXHrrKP7AEbEQqT9H0SQs9__brolJX8mkKJrmIwi4uSKZuoKzxa-qM8xU9beBIsTAksHXAToDy_AdKJkvHmogeUBFClaDhX72TaYbOhvoeKkmizJ9I5iwa4rtXn-mHV-gjUggsllk70K7tOu13lx5B0NlhdXKjjzX-khGajhsHcG_HZb4HTF8R9zC0JUT_yHFW-BHfXb0ds2W8D7-c2l0mUW8gBOiDD91XawJLVnP_2O_v`

* :calling::zork,call_b8f304f721f349df920e220b0137ef68
  > * command `"take guidebook"`

* :scroll::call_b8f304f721f349df920e220b0137ef68
  >      Dam Lobby                                                  Score: 44  Moves: 64
  >     Taken.
  >
  >     >

* :green_circle::call_b8f304f721f349df920e220b0137ef68

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf533d6a0c819192f99630cf78f1b9,gAAAAABq31M_I4KelBFQF2FDcHlajv32q_u4GN0DfIJkHWrLg2vZAMtA9Akzz15hGs4YCx6CEZ8goPA0M_k8doGioavLthT-sXu1G5x6Q8_QtUGPfAkIvkJ_eMP3GRbeUZa9EaOLQPL-EvN53vvG7zUdgbG8WCvLWbAzFIi9EDAponlQ1orD4ZdfUQ1JmWMpTTFnXt_jHNOyp6qY45LetWaynt55Ec375A88Ae-manwdqLrgn4rK1gZoBKcXJt8puVtC4aVhOuXBmXFul8uWz97Ey9U5Te4LaX14bz2imUOfNjSTi4XNUezd0F4Eu96KGVgFrybyCgHjaXXzdT13x_Tk0JJ59nbpmtGB2O_Xc8nVE3JpmKxUn_mEpTNzBESOQrrTqdw9dceltYL2Zpg-rPNTKzbMIMjMFSsD2eqtwd-6KR-PGwPkuR3kk2TijDh6apGS5RqlPtT9QgSTWsmSGryJ4nyMN2O50U_UGsmhb6hl9Lw3TPDApqXAxngQEORr46xRK8i8-RAkyYe-U5zQvShZAcVOTq67VBxubbVycpmtwOmLoKc4JGUAFhjBoxknYg_u15jZXs7sZNWhCaa3yW9MdS9J2czLjUz6anXadAuhp_MgsOT_R6oMUPUOSvVA-wyzx5JBtkoSfqMVdAu8DDExBoG0a69eeJVbsBXd7kiZ2w4QSL0mkDltKqVhGLh-WAO1bH88vX6fulBA_2FUGtouBPZ__0fUUchwi0Jyg4XOqwHjIww0e8gUHjxz1JJp_f1UW8kLwQDKAZfY3CP9m5JeAQKOkD_DuwtZkxipBp2iiJtNSuTxBcNLcQu4cNDGqKL7ytLlQI1wPasoQjufBcEmUkaRGygjKpjYLLHWVg1Lnsob9lbiKIRrIHDVgAeMkW6VnhvwstdQuCGjChG2uy6amFpR-jdXhCNP9OGaFbHSjjWAOoTPhPyds6moOW4fF8RJNzYse1yQvG0J5vV5QbJk5ks-jqo_X4rwQEnmbB5zsSekR8m9aeiPsXzQHNG56emnX4Ux4pA7SSbehI9WjQIlSxk_oKSPRUT95OKYCHoqVqle4fJbgpodXTbpNlgqIl6c5x8pRc4whP7UjflzSy4HCtmrQlMnzsC6YppINyPAHbnPWGYjjHSg1QStS0gys6SzW6C0pwGeV36rXu8tjCYROLZBC1-r4771vT5hfSS7MZHRELEFyBjfq3gzhjPW5lo-RsRSigSZ58k8k0G3AYG3_JqZ_VSJPyedSKsxmMtP3G-qrh2sZrI5L-JFfctqZodYQaUjXWD1c7w8GXRaPv8UYNPkS90ErPTGW9WEahGqIJhggHROLs1XaZEMsfiZHF7kfjtKSUBTTJJvevLVQBr187UynHWVPCqddxqqoeErEwwfLSfDdPRG7eoe_4aV2M1WgFmTDP4otDICDqaOV0siO7MU-vo6F8Xlhn32yEzDWjXAljRNsysz9aJrytyv5R_5USfb45sTc0LSvyiGFsBjruVXLClBmgCPoDdAKKtow2L2ZFAfu4eOKfG68tSfUa7XuWE4Js3KoczIXX39GUTLQ51iidBDyA==`

* :calling::zork,call_6eab7f05f09c4531ace8c83a5a3ba41b
  > * command `"read guidebook"`

* :scroll::call_6eab7f05f09c4531ace8c83a5a3ba41b
  >      Dam Lobby                                                  Score: 44  Moves: 65
  >     " Flood Control Dam #3
  >
  >     FCD#3 was constructed in year 783 of the Great Underground Empire to harness the
  >     mighty Frigid River. This work was supported by a grant of 37 million zorkmids
  >     from your omnipotent local tyrant Lord Dimwit Flathead the Excessive. This
  >     impressive structure is composed of 370,000 cubic feet of concrete, is 256 feet
  >     tall at the center, and 193 feet wide at the top. The lake created behind the
  >     dam has a volume of 1.7 billion cubic feet, an area of 12 million square feet,
  >     and a shore line of 36 thousand feet.
  >
  >     The construction of FCD#3 took 112 days from ground breaking to the dedication.
  >     It required a work force of 384 slaves, 34 slave drivers, 12 engineers, 2 turtle
  >     doves, and a partridge in a pear tree. The work was managed by a command team
  >     composed of 2345 bureaucrats, 2347 secretaries (at least two of whom could
  >     type), 12,256 paper shufflers, 52,469 rubber stampers, 245,193 red tape
  >     processors, and nearly one million dead trees.
  >
  >     We will now point out some of the more interesting features of FCD#3 as we
  >     conduct you on a guided tour of the facilities:
  >
  >             1) You start your tour here in the Dam Lobby. You will notice on your
  >     right that....
  >
  >     >

* :green_circle::call_6eab7f05f09c4531ace8c83a5a3ba41b

* :thought_balloon::**Checking the Dam matchbook**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf53426f4081919329dd49b5742afd,gAAAAABq31NIiq968QrCGhnlydKSRf5QwVhb3qNEHQiYfBR2i9feSy52RnCExcFbTaKWQDO1A5uEWEMN1KmmFd4RRTIZfl6WREx8MU7nqiyM54PSBojS3p0FtQTQoIzeR3CDjBax49mZhnzSA1_xdTinspOjv3FcddWHzTK7arcY8tYyV1mJPqB-sCin8pdvOc_GNQuqvT29TDAeMRRputXmYnweDVSMfvY0_6zYWLVp9f2BbyMNGg8nLNBR1Gj-aUxDKe4TbDH55PPYqx__rhLauLjMl1vBr6O0H1ZFTtpAYZ601_YVWH3iSdFRIZuPiHwqMRYhcXhfJm3uHOUXPyLchiw4Ne4I_W0KLRiFa06xB_HFtq2ieI8h5dCdV7N46nT8-c96Y3qoeH_Evt3NZtmwmZoGnGU1MbU-eYyCil6iqtRlZVGmfqmYc52drgNk9ehm8SgG10nGXILRsWpQAxN55nX_fmLjOc-ea7n_-JnOzYzUQvBj9wBL4raWBw0T9R-kI_W-XcDiF4fVuwz6dyc98Cmhn8KDp4fdTF866rcJgR4gsxwxfSq-7V66f_-iEnWtW0Fcj7vpUk4C9J-FE-4EaH2VZKT2Vo1SwzOfnwTtgP5YNsBWcBrnld2H5exfmV8jt-I4Jfpbluzu6ieG-5eRQZLLzfxd2OK-PCznmoy46_QFgKsjkMef4oVFNWPiZlhCXpBA5zgti_3gQI4J3MFCFTOpNOqRb6eTWrC7vleOnR5GM7tOJ6QUMQY6NJnXTQSGyvtH7baYsPPHppw_B0K6U6_MqUk77d8Tb1rh4uM3o3EaQzpa6TaADApfWCL-Ot7hY9HcvQ2iRXljVr8aDVvkwyNYz3vwqSS9BgroWpVV7Gm3gO4KDxKtfbnu9Odo5Zt-2QRHXEGS-NCjuEPvjMushKAoXRs4bjAd7YuUKRKZwkT1sRwucQsR6CfqwEvIFUBe19TP_bDghcHclvygpDkQ1pXNM2YOJaq7Ku0eS_2MhcFuN4WFI3rjXKb3Zk8hGG83e5QFtR3GclChLwx_WmL79HtoHwzS5yaWjkrcCnEBLDNPYyZ3v8PFddYLgFoXTz6uvt0reD75_sDse9F4ggpIiT5emMsHlU-noScHDps0fUEEuE4Xhiu9whV8CcrJvl2fN8tDQXndsJ-uKVI55s_4Lb4Sr_0672AW73BWfDpDx0eFT4txC6wtX5Zec-ey5mM_Rg-4NmiOtKey-TNW1wW2QBM3_J4O-gRLXc56tQ3iyQMOhXFlTEJ-iqDEq7Di8gICrKJAbMd9k1IYWTfR45xvORX3HlSGJc7a1z3zLd2kNacqS6TMWXm3PqiJuC1nFhmndxfYHlVFVXhMWmQv3P8pcNbp8bNW90VzjjGeApQJtdusHAe_eX00REzYGkQ-tTDOcUC5R8dTU2eDg7ypXGT6WZI-FCPTNB1P9u3MPgajEwd6fTy7ELlaz9IWtv3BIN2oc8xl-XbgyZMul2Sc7W27HpaGdZROrzV0fRWJw4UsHx8ofNo-uadL9NvZsL3Wd7_D62l1Lm284b7lvcmvjL8dMC_SnbVuq5tIaYEycvh4SyfnvGaT1No9_XjInv6f6JgGjrlTWelE2oymyRsTqD7oEqqM_njjYV7Z8Hu_MOS-ugSsE6dCM_L9GWYg0PpA1S8MbfnTrlRLW-mpiewdVOhMD9rnJpyUmHVsRhQHz91-njYb5_K9uvprMGhukw4hv7eJG2QgLSUdV9-J6ESwEWYLpbQxmcsP19G2Vp1bgy6YuJ1OuxKzBzrrXCtN23UAv1EIbUIfO-POrLzDO7j_33EtnHen-I8IVxnO7uZTA7VMItAnqyF_B867gjQ91HSVVt-TRUwpVWPtH4GQcBTmPhk7xnv60ajkk9SDhpjtNWo6Sg1QnP-kxQg7Q8xTrs3vXNxdzcBnKucfK5vhYolvry9xVhYMo9MDlxoFp4Mr_DHr3dsqmnz5qpoLkFTB_hgd_80ustvsCE-7qIwIZpSDGRLl1U7HDU1sDSKtZKn5dEj4xdqb-NSf1xxa8-6Yot1IWb7MnW6rwzNivxZBU0pDfQwplPoNQwXDFzopRQZqkzwCBfBusXGjjZDwuC9-cueahZsQULsHB1PtjJYndyFdDPJVdRJgf_jxJxrqbK5bD1ZfcPwLHYQSmgeJ1wppGowwqTtCxS5ziHQyrWajX3EKF2c-Za7ZZU-1ZsEbXs_MMtuwKWaWrAW-9ww=`

* :robot::
  > We’ve made it to **Dam Lobby** via the Round Room, North-South Passage, Deep Canyon, and the dam. I picked up a **matchbook** and a **dam guidebook**—both useful finds. The guidebook starts a description of the dam tour, but I haven’t touched the controls or tried crossing the chasm. We’re in the lobby now, with private doorways to the north and east.

* :raising_hand::
  > Should we note anything in your journal?

* :thought_balloon::**Checking existing journal**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf53fae37c8191a870fbbae46d343d,gAAAAABq31P8mnkRuKPekc8cmGgVYIy8PLdHq6Mkrx6B_hhM21DZgKVqaWKx8bz1-uUOTtuST71WMS9V29iBHvkfAvqChkRylHvvwzI-xFjvFEe-stbCj6W4jjKO49RhVQChhOWXwHQx7O0-orVgjzFRzHUpZsvqbJLBYPaGSWN5Ys41d7tK-kUYySFtUlH5XF6V7Ddest0PYcDDCLq8YQ0xvQOJS7fayoOwqfeQ4umwt3IeDXJOCDxg38fp1PvrDQLc5y9DpudIve2NQLftwa1Ik43HOKpYL1Mh7uhzeJsiEPwuCEcWqnQO9K214Kx0OcJu_MuOaHVRRPP9rpGpoS_gO6A6gvCa9D5WNx_M6SJnFh9uWkopyj_c7hs4ijGpQqNpYs10kjlpOPNT2mJ3IvyJu0fWRviNwLKiXf2CJYKxC6PXYmbtKWiSPeSr6QikNxTBYHlOA5FipBThYkz5P4ryVgdGdbsuT432h2Tv2TRG_lIdHOR573KUyQsu4WsFh5lwgMOz6Ixf-1IpN7wr-kvrC7zt6E9eVEptnGzWXeftWJU0SZvwTUmXA4qFH8xGnloWmT-uomSjNJVAFzl5fpwtRSL3upp1k61OaWpbharcYeWdWIdM4RNwO9OCgkxwwQlKwA2P2ok0CLwpDWVI8JkUov1wudnBSxFnDhpCxN0UYihqreoaynALt0SzN6bkqi5lSSt4_ZCG7ExOm3ERbnuvmxnXTeJq6QMo5dpsNgH25ppq4n3ATCPWV3KktHsGBbmHab6Uc-Regr2VG6Xjy1aMcBnIIhuZHOtQULlqLQUVq4CRg4e93Q1kyhwk-ptH8VlQcUvYyZP3Plzyv8wgNgFFmfDc2IUY-n5iqqemECRLNtzirclsFvqU10BD2dCTN_izi-Ygl33Idm2n7UZMFJ8r4yBQWf7rKBTDsBrn5FByKV_XP-2IWuFqreqt9SzJA3AGR9caALKcsnkmRvVPmgy8MzCSVRTvk0S8dg7VJJy10gcFrd4O4wiI058nhi47JvTotrJkcIdJS87vsFLrc7V6Wk2tdyj-WNdQVSrOr62Ui13SLUGid3hqIGDk_e-O0xEVfU3nNsnByfl-YULBN7khhpqzEFg7LjNsGG_NV4ntDtRG-zqXm-iMWEAH5Q56vQqthmxN4rxq7KWTTR6gxBgq4BYhp9BshBxwxJ2iQt4XhMFVIlPNsrxVfPwCgI6E0EMdHR3oRNC4xYSfk3ovTdGeh39NmvCbWofWEpdyZSis6XYCBDh7FYL46nrDDxmURz1jTEHzrmv15KM3OlfajqAronXmS9QWcT-mwhi2DK_O9aLdSNFTHlomU2dN9LW02uoLAR2WLOVywByQfbt5TLKBP8BgIgVfat6z0ryljkc7t6V0jjTh30FfyQ-ekiZ-AMdC0HOSe7PHkYA1-I-fAq7N3ePAeKiZv9kV1DlBc7K-zVAtiGMUxJt2qHaJLkfXBsznqfmwoI2OsA_uHgZJmcARo7IHsqq-I90Edi1VuvMdOkQ7VY_uvOferZ6rGOfIlaWHHOX2rEy1kLqhltUD0Pwsdwn_AH5a6oB7CkgBR19dZ21LQIzpLa6nA_Gxr5YI4jVPu8ZQd7koKe8yvNmYb-5Dbh-Wa5Cg7FTnOSyu7gb_vOlNsorWKZXB2aG_JqNJOT9ewk8jaWe3AKKfY9iA-xPn-9IXxwY5GyKbEg8ZVwEWXlOPsr2zD_kklUAVMRagfNLrs8wS7uZZgGmTlG56fgrhZGDeWFp5YRrne9db4VA9xvqkxcoKZqRX_Hjfg3HL01LFODKUZrtYwXegRfoJdriYKwKgLIk-UKFjAaHfxBCwo4DFX_3otlcaHn5wW3wy-9GYdtdN8ZfA6KWzqwe4kUkk0mai_zbWJnLCCYvAXMTkv80tWMsZI10=`

* :calling::read_journal,call_fc8e609a8eae45319cde62f7cc01bcc0
  > * pages `"1-10"`

* :receipt::call_fc8e609a8eae45319cde62f7cc01bcc0
  >     ―――――――――――――――――――――――― [End of file] ――――――――――――――――――――――――
  >     [journal.txt: Pages 1-1 of 1-1. Lines 1-1.]

* :green_circle::call_fc8e609a8eae45319cde62f7cc01bcc0

* :thought_balloon::**Adding journal notes**

* :thought_balloon::snip
  > :lock_with_ink_pen:`rs_078b0cc6882097a0016adf5400ad1c81918ef0162ff4770b1c,gAAAAABq31QEqkay368x5zMXQ6KzeRq1USk7fOlSMuFyUlL7fZ5yQ6yQIJcGj8M-mHT1GQsIbcMsC_jzsvPvjAvdJw8E2JV6-zjsQxFUaQpF_RIjKxijYjUIp8-P6qoNx_zx1SWuLZ29YnpIbOik950Ar5fvmVJZA-qX5MIvBurjNg1fR8_hZY8lrNKSNTCfbNPiLG_owGuU3TfijoXeHkbF4xHBNg1hsrRuUaetCdPneAr2nLdZYa9tS48KYnbBMu7-zn8r6olTLPPnKhJ0fI-YBKmwD-SJfYg75o9_VWf5ghjeMfR8y20GozG_x-G8-B0koXHIcipjcHI7NBm39zG0pwCDzuuD-Jr87GNJrS6Uz5WlFExbiLyQgKL2bEy4NMFKYaTdvIfVn7ZliAZHVlmrk9pgcjqJlNgvobIhw5rvVsQ7hs_sOjP_YjDQHbOuO4bYc7-qxBcQp0_1Ofmmkr0aTHQJ1ysbq62xJCUcwXSCuErpSbPeexH0y0spt2-ignCTVAUNzaF7WuBaak9GpWcl51DR1UxsGMy09l3p1CKsfqZCoS1E0vemIuZtJSO9hCVFT2YrvgYUnnwkDL89yUxYayBW2XqQa49U5FKYmbCEonxfgmkedYU-fu91LZDvpY2VYiCzjH08bSR6wakKqVuMC2Ty6fMTH-qOn-Sav6N5tZnbI95tw80MSPeEvdDg2N--gwty0KbxbblzrbLTZSmBnWnufOZVhCyPRbKpxNL1UtnwcODSkuP6ziBUJwWHj0s4UEHRWW10pH_71iWSKF_ZX-6BZeVQC_NZE6SGhKV6LWBKzGgV9loOoduZuv6dmuTnfgrXi2dkcSbhk3cD8ayRS0QslGRgLacSvY2EsU5ba10mxaQ_j6YMzqt7ZbbKxNNDEiWLkWZrJLqufjgLc8w0X_XtuBCPMvJKBE4XHeJel-v-8UIMYDY42HDpl-5ZsnWQnClFLbdcLqOmDh5hk6wTsdxweovX7dXBBYIJgDp3GGAW2EiWuSQ5TQ9YLrFI-BZ5pGBEMuO0YfLnN_QcCYz5-TIVf8vW2F6Ox1qcZgr-34L4PCHXSmUaw2uoseoDZNg5dvx0_DIAmbeKf3TPqTJvED-ek0ty6TbX0v06fuRxum1OF8Rp-4whYtMhPeFf7-2ArMBBS8iRpbBSz84i-JvaKRreMzvrSZu-WvMQ0FiS0UMQ9UD96AbsMjJosuf2F2dGRQc-Y2VBvqWewaakHJcS9W3KLk2qAbDWEK3s6Ca_5yS0v9HcuKQCdlOUA9mehzq911NmtIbV2tLuRse44GR8Ooihutdah57qHF29Vgmk9Ge94wxCCAXeR00gpgwVmv6B8818DpqJ-wG7HUvrtwbXOyyeyi2PzWRLUy457GkGXa8TiMcm20YP-3yHoFNJ5EXaHx5y1PkmYisEjch13PZdHuY3zIMjKOofm0nItjfq539KQz5b_9I6pCE19FXPid8jHEOzhfU65Gu9cPAsHPBr9Lyyxq65ZOdhgYvt13yfAU44pZ-gImKYh3epNDsLv_k4jw5K60UGPB2mXCZ_iUVPw4xrkQuKVOGxECQ7k4-eow2TwYF-sPcthZKH9Q742ZlKWKW9TP2UtaprY8H5le31zEkzZ6YNoAHBpzve8IDZheHzqv7MjwyenuqSW9mfNj6o90ccO3HS1KOXtxzL51t3r41g0e6UTQaDYs16kIsQnM0wfEayN9X-epXTxgcsvgSEMme1nDDWlZ6U7q3FzDQhmbbIP02NtT8iLkAuTGCOIEEPsZrit-p9S_1wUGM21kIRxzrs1GTgZwjowp83rJEDJxqaWX7Z8dgJiU8RM22ZQdZEVWiaeHWrCsddM_EOekxQ4xAClrL19Exb7kKCPibHryzROdQsJKRdvPIrdCMMADpBUTEjgMKnFsduqmQGUA-oojLsAC2wNZx7AeUk22mWf1s5jOuKhsKCo6Qr95L0AOwwjefvdznXQ21fr-qyRQLGk2xsNN9v6iIgPECgbIzCcQStykTQhK6aXDjrf-5FwboPjtWS2UR2bor7qL4DgEn5nR0ElatmSL8_vYYZg2NuRbHfZMIvcIT-IZK2ZcoCw2FpdXgQnQwuZxrwtlmzG1P7Pl8SQSR8jQjDJWeD0PQI44wxYd2Cqhm4edUGadMHiyvULNhDtiiar_IUSuO6F9cWg8e0uonb2OsBJC8iBAoSHQblFmn9Bev3BID7CoI799PC9O4DG7Rif4dLe-pikL9cNaLnjnCRfcCrPMbto2vI2oXok6HphrfxAXVDBIzbYIxnT2q1-oSG7jhdv2A-_L_0-sQdIzKxNN-bQlNJPOE5oR-w8cTqp6AHFm3GcSd4Yw5aFcLimatJZdb6z0LcE-EeQp0eE7conTgC-Pqs_G0i3ygdJt4901ZEYGJN6oYV0K5J9eVlF7nz2CXblXQReRhpucxP1wogUv-ftzFFhf6yJRbY81TGKUqq-GE4m2kW-WvvetM2ju0xwv8GJJEODD2aWoGuHVCd78ri_uZcyVOjfheKns9eJmK83uqm8ZytOOnPeq12Kfru79xJSUuVWziFJxRjDLNXvsK-xCE6ZgM1i_ElFO8IN3IdsCDP79L1U4gslqf_mdFuiahViQZHx46b9zWztlhotDEbkSdQSzULI7vjcb359mErSv6jLFh6JHDgwGp_JJHali_Rsa1A-S1vm5V_x6nt0jCBy2sjrZjmFYgpl6B6QA==`

* :calling::edit_journal,call_164582a1350747998513c11bfd1a6366
  > * new_string
  >   ```text
  >   ZORK I progress (Score 44, Moves 65): Entered the White House through the slightly ajar window behind the house. Key starter items found: water-filled bottle, peppery brown sack, elvish sword, brass lantern; lantern is on. Opened the living-room trapdoor and descended; it slammed shut and was barred above. Killed the troll in Troll Room with the sword; bloody axe taken. Troll Room currently has the brown sack. Painting treasure was dropped in Troll Room when overloaded, but later wasn't visible there or in Gallery; its whereabouts unknown (thief is only a theory—we have not seen the thief). Leaflet was dropped and later found at East of Chasm, recovered and read; it is the Welcome to Zork leaflet. Troll is dead; passages from Troll Room east to East-West Passage, south to Cellar. Explored East-West Passage -> Round Room -> North-South Passage -> Deep Canyon -> Dam -> Dam Lobby. Current location: Dam Lobby. Inventory additions: matchbook and Flood Control Dam #3 guidebook. Dam controls not operated; chasm crossing not attempted. Living Room trophy case is a likely safe place for treasure once we regain access.
  >   
  >   ```
  > * old_string `""`
  > * pages `""`

* :scroll::call_164582a1350747998513c11bfd1a6366
  > ```diff
  > +ZORK I progress (Score 44, Moves 65): Entered the White House through the slightly ajar window behind the house. Key starter items found: water-filled bottle, peppery brown sack, elvish sword, brass lantern; lantern is on. Opened the living-room trapdoor and descended; it slammed shut and was barred above. Killed the troll in Troll Room with the sword; bloody axe taken. Troll Room currently has the brown sack. Painting treasure was dropped in Troll Room when overloaded, but later wasn't visible there or in Gallery; its whereabouts unknown (thief is only a theory—we have not seen the thief). Leaflet was dropped and later found at East of Chasm, recovered and read; it is the Welcome to Zork leaflet. Troll is dead; passages from Troll Room east to East-West Passage, south to Cellar. Explored East-West Passage -> Round Room -> North-South Passage -> Deep Canyon -> Dam -> Dam Lobby. Current location: Dam Lobby. Inventory additions: matchbook and Flood Control Dam #3 guidebook. Dam controls not operated; chasm crossing not attempted. Living Room trophy case is a likely safe place for treasure once we regain access.
  > ```
  > [journal.txt: Appended to page 1, changing lines 1-1.]

* :green_circle::call_164582a1350747998513c11bfd1a6366

* :robot::
  > Yes—I recorded the key progress and locations: the troll is dead, we have its axe, the sack is in the Troll Room, and we found matches and a dam guidebook. I also noted that the painting’s whereabouts are uncertain and that we haven’t actually encountered the thief.
