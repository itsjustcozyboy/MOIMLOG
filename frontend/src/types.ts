export type Person={id:string;name:string};
export type Attendance='unknown'|'yes'|'no';
export type Sharing={participantId:string;name:string;sermonSharing:string;lifeSharing:string;prayerRequests:string;prayerSource:'explicit'|'inferred'|'none';needsReview:boolean;warnings:string[];sunday:Attendance;youth:Attendance;meeting:Attendance;qt:Attendance};
export type Report={meetingDate:string;leader:string;meetingSummary:string;participants:Sharing[];unassignedStatements:string[];warnings:string[]};
export type Meeting={id:string;meetingDate:string;leader:string;title:string;sermonTitle:string;question:string;participants:Person[];step:number;status:string;text:string;segments:{speaker:string|null;text:string;timestamp:string}[];mapping:Record<string,string|null>;report?:Report;mode?:string;audio?:string;job:{state:string;kind?:string;error?:string}};
export type Profile={id:string;email:string;name:string;community:string;members:string[];retentionDays:number;isLeader:boolean};
export const statusLabel:Record<string,string>={draft:'작성 중',review:'검토 필요',complete:'작성 완료'};
export const dateLabel=(s:string)=>new Intl.DateTimeFormat('ko-KR',{year:'numeric',month:'long',day:'numeric'}).format(new Date(s+'T12:00:00'));
export function reorder<T>(items:T[],index:number,offset:number):T[]{const next=[...items];const target=index+offset;if(target<0||target>=items.length)return next;[next[index],next[target]]=[next[target],next[index]];return next;}
