
### Splits: case lines whose two runs differ, normalised

- X 1/a-200-transfers-20-live: 649 of 1387 lines differ; first at guix-8.20.0-1.log:63 / guix-8.20.0-2.log:63: "t 1 a-200-transfers-20-live step=6 => ok status=200 version=http/1.1 url=http://a.localhost:#/1a?tag=T&sc=6332303D763230&sc=636F6D6D6F6E3D3230 connect-us=~ tota" / "t 1 a-200-transfers-20-live step=6 => ok status=200 version=http/1.1 url=http://a.localhost:#/1a?tag=T&sc=63363D7636&sc=636F6D6D6F6E3D36 connect-us=~ total-us=~"
- X 1/d-close-crossing-submit: 670 of 1479 lines differ; first at guix-8.20.0-1.log:1477 / guix-8.20.0-2.log:1477: "t 1 d-close-crossing-submit step=2 offset-us=~ submit-minus-close-us=~ => ran  close=ok closed state=closed holders=0" / "t 1 d-close-crossing-submit step=2 offset-us=~ submit-minus-close-us=~ => ran  close=ok closing state=closed holders=0"
- X 2/carry-SHARE-2: 1 of 16 lines differ; first at guix-8.20.0-1.log:3197 / guix-8.20.0-2.log:3197: "s 2 carry-SHARE-2 cookie "Cookie: k=1"" / "s 2 carry-SHARE-2 cookie "Cookie: k=2""

3 cases differ between runs
