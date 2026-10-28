import {execFileSync} from 'node:child_process';
import path from 'node:path';
export default function setup(){execFileSync(path.resolve('../.venv/bin/python'),[path.resolve('../scripts/create_test_template.py')]);}
