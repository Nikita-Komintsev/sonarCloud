<?php

return function($job, $sendResult) {
	$result = [
		'result' => 'sign_verified'
		, 'docid' => $job->docid
	];

	$doc = $job->full_doc;

	foreach($doc->signers as $signer) 
	{
		if(!@$job->allowed_signers->{$signer->id} ) {
			$result['status'] = 'doc-sign';
			$result['status_message'] = 'Подписаший не может подписывать';
			error_log($result['status_message']." $doc->docid");
			return $result;
		}
	}

	//FIXME: use FRESH (daily imported) islod intead app_spec_list

	if(!$job->app_skip_license) {
		if(!@$job->doc_license_props) {
			$result['status'] = 'doc-sign';
			$result['status_message'] = 'Нет лицензии';
			error_log($result['status_message']." $doc->docid");
			return $result;
		}
	}
	if($doc->gov_doc && !$job->app_skip_acred) {
		if(!@$job->doc_license_props[2]) {
			$result['status'] = 'doc-sign';
			$result['status_message'] = 'Нет аккредитации';
			error_log($result['status_message']." $doc->docid");
			return $result;
		}
	}
	if(false && $doc->docdate < $job->status_stamp) {
		$result['status'] = 'doc-sign';
		$result['status_message'] = 'Дата подписания после даты выдачи';
			error_log($result['status_message']." $doc->docid");
		return $result;
	}

	$signatures_CN = [];
	foreach($doc->signatures as $signer=>$signature) {
		openssl_pkcs7_read(
			"-----BEGIN PKCS7-----\n"
			.
			$signature
			.
			"\n-----END PKCS7-----\n"
			, $m);
		$cert = openssl_x509_parse($m[count($m)-1]);
		$signatures_CN[$signer] = trim(preg_replace('/\s+/', ' '
							, mb_strtoupper($cert['subject']['CN'])));
	}

	$err = false;
	foreach($doc->signers as $signer) {
		$CN = @$signatures_CN[ $signer->id ];
		$N = trim(preg_replace('/\s+/', ' '
							, mb_strtoupper(
								$signer->i[1]." ".$signer->i[2]." ".$signer->i[3]
							)));
		
		if( $CN !== $N) {
			$err = "$CN ≠ $N";
			break;
		}
	}

	if($err) {
		$result['status'] = 'doc-sign';
		$result['status_message'] = "CN сертификата подписи не совпадает с ФИО подписанта ($err)";
			error_log($result['status_message']." $doc->docid");
		return $result;	
	}

	$req = "";
	foreach($doc->signatures as $signer=>$signature) {
		$req .=
			"-----BEGIN PKCS7-----\n"
			.
			$signature
			.
			"\n-----END PKCS7-----\n"
			;
	}
	$req .= "-----DATA-----\n";
	$req .= $doc->signed;

	\az\messaging\MQ::HTTPSource(SIGN_VERIFY_SERVER)
	->content($req)
	//->log("http verify sign ")
	->PUT(function() use($doc) {
		// 200-OK
		// send to archive
		// 1) make request
		global $archive_fields;
		$args = [];
		foreach($archive_fields as $n) {
			$v = @$doc->$n;
			$args[] = is_object($v) || is_array($v)?
				json_encode($doc->$n
					, JSON_PRETTY_PRINT
					|JSON_UNESCAPED_SLASHES
					|JSON_UNESCAPED_UNICODE
				)
				: $v;
		}

		$fields = implode(', ', $archive_fields);

		// our_date - filled by server
		// op_stamp - filled by server
		// op_seq - filled by server
		// op_sign - signatures
		// op_sign_stamp - signature stamp

		// make normalised data
		// 1) sort fields lexicographical
		// 2) escape dividers
		// 3) join with names

		$sorted_fields = $archive_fields;
		sort($sorted_fields);

		$merged_data = [];
		foreach($sorted_fields as $n) {
			if(isset($doc->$n) && $doc->$n !== NULL) //skip nulls
				$merged_data[] = "$n:"
					. str_replace('~', '~~', '???' /*@$doc->$n*/); //FIXME: string converion
		}
		$merged_data = implode('~', $merged_data);

		$merged_data = hash('sha256', $merged_data); //TODO: replace it with signature

		$args[] = $merged_data; 
		$args[] = (new \DateTimeImmutable)->format("Y-m-d H:i:s.u"); //TODO: replace it with signature time

		$q = implode(', ', substr_replace(range(1, count($args)), '$', 0 ,0));

		$fields .= ", op_sign, op_sign_stamp";

		// 2) TODO: sign it (or hash it)
		// 3) extract time signature
		// 4) insert holds a shared lock on blockchain
		//var_dump($fields, $args);
		$args[] = $doc->our_number; 
		$last_arg = count($args);
		return \az\messaging\MQ::MQPG(ARCHIVE_SERVER)
		  ->executeCommand("
		  		WITH ins AS (
		  			INSERT INTO docs ($fields) VALUES ($q)
		  			ON CONFLICT DO NOTHING 
		  			RETURNING our_date
		  		)
		  		SELECT our_date FROM ins
		  		UNION ALL SELECT our_date 
		  		FROM docs WHERE our_number = \$$last_arg
		  	"
			, $args)
		  ->getOneValue(function($our_date) use($doc) {
			// successfully processed!
			// set our_date
			$doc->our_date = $our_date;
			return $doc;
		});
	})
	->then(
	function($doc) use($sendResult, $result) {
		if($doc) {
			$result['status'] = 'issued-ok';
			$result['status_message'] = null;
			$result['our_date'] = $doc->our_date;
			
			error_log("OK $doc->docid $doc->our_number $doc->our_date");
			$sendResult($result); 
		}
	}
	,
	function($code) use($sendResult, $doc, $result) {
		// err
		if($code === 417) {
			// not verified
			$result['status'] = 'doc-sign';
			$result['status_message'] = 'Подпись не прошла проверку';
			error_log($result['status_message']." $doc->docid $doc->our_number");
			$sendResult($result);
			return;
		}
		error_log("unexpected result code: $code");
		// something wrong ....
		// DO NOTHING!!!!
	});

};
