
### Item 2: curl_share_setopt's answers (CURLSHcode: 0 OK, 1 BAD_OPTION, 2 IN_USE, 5 NOT_BUILT_IN)

| call | cite | X |
|---|---|---|
| SHARE 0 on a fresh share | X guix-8.20.0-1.log:3071 | 1 |
| UNSHARE 0 on a fresh share | X guix-8.20.0-1.log:3071 | 1 |
| UNSHARE 0 after SHARE 2 | X guix-8.20.0-1.log:3071 | 1 |
| SHARE 1 on a fresh share | X guix-8.20.0-1.log:3071 | 1 |
| UNSHARE 1 on a fresh share | X guix-8.20.0-1.log:3071 | 1 |
| UNSHARE 1 after SHARE 2 | X guix-8.20.0-1.log:3071 | 1 |
| SHARE 2 on a fresh share | X guix-8.20.0-1.log:3071 | 0 |
| UNSHARE 2 on a fresh share | X guix-8.20.0-1.log:3071 | 0 |
| UNSHARE 2 after SHARE 2 | X guix-8.20.0-1.log:3071 | 0 |
| SHARE 3 on a fresh share | X guix-8.20.0-1.log:3071 | 0 |
| UNSHARE 3 on a fresh share | X guix-8.20.0-1.log:3071 | 0 |
| UNSHARE 3 after SHARE 2 | X guix-8.20.0-1.log:3071 | 0 |
| SHARE 4 on a fresh share | X guix-8.20.0-1.log:3071 | 0 |
| UNSHARE 4 on a fresh share | X guix-8.20.0-1.log:3071 | 0 |
| UNSHARE 4 after SHARE 2 | X guix-8.20.0-1.log:3071 | 0 |
| SHARE 5 on a fresh share | X guix-8.20.0-1.log:3071 | 0 |
| UNSHARE 5 on a fresh share | X guix-8.20.0-1.log:3071 | 0 |
| UNSHARE 5 after SHARE 2 | X guix-8.20.0-1.log:3071 | 0 |
| SHARE 6 on a fresh share | X guix-8.20.0-1.log:3071 | 0 |
| UNSHARE 6 on a fresh share | X guix-8.20.0-1.log:3071 | 1 |
| UNSHARE 6 after SHARE 2 | X guix-8.20.0-1.log:3071 | 1 |
| SHARE 7 on a fresh share | X guix-8.20.0-1.log:3071 | 0 |
| UNSHARE 7 on a fresh share | X guix-8.20.0-1.log:3071 | 0 |
| UNSHARE 7 after SHARE 2 | X guix-8.20.0-1.log:3071 | 0 |
| SHARE 8 on a fresh share | X guix-8.20.0-1.log:3071 | 1 |
| UNSHARE 8 on a fresh share | X guix-8.20.0-1.log:3071 | 1 |
| UNSHARE 8 after SHARE 2 | X guix-8.20.0-1.log:3071 | 1 |
| SHARE 9 on a fresh share | X guix-8.20.0-1.log:3071 | 1 |
| UNSHARE 9 on a fresh share | X guix-8.20.0-1.log:3071 | 1 |
| UNSHARE 9 after SHARE 2 | X guix-8.20.0-1.log:3071 | 1 |
| SHARE 99 on a fresh share | X guix-8.20.0-1.log:3071 | 1 |
| UNSHARE 99 on a fresh share | X guix-8.20.0-1.log:3071 | 1 |
| UNSHARE 99 after SHARE 2 | X guix-8.20.0-1.log:3071 | 1 |
| SHARE -1 on a fresh share | X guix-8.20.0-1.log:3071 | 1 |
| UNSHARE -1 on a fresh share | X guix-8.20.0-1.log:3071 | 1 |
| UNSHARE -1 after SHARE 2 | X guix-8.20.0-1.log:3071 | 1 |
| option 0 (NONE), value 2 | X guix-8.20.0-1.log:3071 | 1 |
| option 6 (LAST), value 2 | X guix-8.20.0-1.log:3071 | 1 |
| option 99, value 2 | X guix-8.20.0-1.log:3071 | 1 |
| a share a handle holds: SHARE 3, UNSHARE 2 | X guix-8.20.0-1.log:3071 | 2 |
| a share a handle holds: UNSHARE 2 | X guix-8.20.0-1.log:3071 | 2 |
| a share a handle holds: cleanup | X guix-8.20.0-1.log:3071 | 2 |
| cleanup once the handle is cleaned up | X guix-8.20.0-1.log:3071 | 0 |

### Item 2: what a share set so carries between two transfers (make's codes; what the second sent)

| share | cite | X |
|---|---|---|
| carry-SHARE-0 | X guix-8.20.0-1.log:3154 | (((1 0 1)) 0); second sent none |
| carry-SHARE-1 | X guix-8.20.0-1.log:3170 | (((1 1 1)) 0); second sent none |
| carry-SHARE-2 | X guix-8.20.0-1.log:3186 | **(((1 2 0)) 0); second sent "Cookie: k=1" / (((1 2 0)) 0); second sent "Cookie: k=2"** |
| carry-SHARE-3 | X guix-8.20.0-1.log:3204 | (((1 3 0)) 0); second sent none |
| carry-SHARE-4 | X guix-8.20.0-1.log:3220 | (((1 4 0)) 0); second sent none |
| carry-SHARE-5 | X guix-8.20.0-1.log:3236 | (((1 5 0)) 0); second sent none |
| carry-SHARE-6 | X guix-8.20.0-1.log:3252 | (((1 6 0)) 0); second sent none |
| carry-SHARE-7 | X guix-8.20.0-1.log:3268 | (((1 7 0)) 0); second sent none |
| carry-SHARE-8 | X guix-8.20.0-1.log:3284 | (((1 8 1)) 0); second sent none |
| carry-SHARE-9 | X guix-8.20.0-1.log:3300 | (((1 9 1)) 0); second sent none |
| carry-SHARE-99 | X guix-8.20.0-1.log:3316 | (((1 99 1)) 0); second sent none |
| carry-SHARE--1 | X guix-8.20.0-1.log:3332 | (((1 -1 1)) 0); second sent none |
| carry-SHARE-2-UNSHARE-0 | X guix-8.20.0-1.log:3348 | (((1 2 0) (2 0 1)) 0); second sent "Cookie: k=1" |
| carry-SHARE-2-UNSHARE-1 | X guix-8.20.0-1.log:3366 | (((1 2 0) (2 1 1)) 0); second sent "Cookie: k=1" |
| carry-SHARE-2-UNSHARE-2 | X guix-8.20.0-1.log:3384 | (((1 2 0) (2 2 0)) 0); second sent none |
| carry-SHARE-2-UNSHARE-3 | X guix-8.20.0-1.log:3400 | (((1 2 0) (2 3 0)) 0); second sent "Cookie: k=1" |
| carry-SHARE-2-UNSHARE-4 | X guix-8.20.0-1.log:3418 | (((1 2 0) (2 4 0)) 0); second sent "Cookie: k=1" |
| carry-SHARE-2-UNSHARE-5 | X guix-8.20.0-1.log:3436 | (((1 2 0) (2 5 0)) 0); second sent "Cookie: k=1" |
| carry-SHARE-2-UNSHARE-6 | X guix-8.20.0-1.log:3454 | (((1 2 0) (2 6 1)) 0); second sent "Cookie: k=1" |
| carry-SHARE-2-UNSHARE-7 | X guix-8.20.0-1.log:3472 | (((1 2 0) (2 7 0)) 0); second sent "Cookie: k=1" |
| carry-SHARE-2-UNSHARE-8 | X guix-8.20.0-1.log:3490 | (((1 2 0) (2 8 1)) 0); second sent "Cookie: k=1" |
| carry-SHARE-2-UNSHARE-9 | X guix-8.20.0-1.log:3508 | (((1 2 0) (2 9 1)) 0); second sent "Cookie: k=1" |
| carry-SHARE-2-UNSHARE-99 | X guix-8.20.0-1.log:3526 | (((1 2 0) (2 99 1)) 0); second sent "Cookie: k=1" |
| carry-SHARE-2-UNSHARE--1 | X guix-8.20.0-1.log:3544 | (((1 2 0) (2 -1 1)) 0); second sent "Cookie: k=1" |
| carry-none | X guix-8.20.0-1.log:3562 | (() 0); second sent none |
